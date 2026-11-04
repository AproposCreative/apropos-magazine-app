import Foundation

/// Explicitly configured, single-request sessions. Construction opens no session
/// and has no default endpoint, credentials, provider or application wiring.
struct PushRegistrationURLSessionExecutor: @unchecked Sendable {
    static let maximumBytes = 16_384
    static let timeout: TimeInterval = 60
    private let allowedURLs: Set<String>
    private let protocolClasses: [AnyClass]?

    init(allowedURLs: Set<URL>, protocolClasses: [AnyClass]? = nil) throws {
        guard !allowedURLs.isEmpty, allowedURLs.count <= 2,
              allowedURLs.allSatisfy(Self.validEndpoint) else { throw PushRegistrationFailure.invalidResponse }
        self.allowedURLs = Set(allowedURLs.map(\.absoluteString))
        self.protocolClasses = protocolClasses
    }

    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await perform(request, awaitPhysicalCompletion: false)
    }

    /// Destructive/account-bound callers retain their physical reservation until
    /// URLSession confirms completion or invalidation, even after local denial.
    func performAwaitingPhysicalCompletion(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await perform(request, awaitPhysicalCompletion: true)
    }

    private func perform(_ request: URLRequest, awaitPhysicalCompletion: Bool) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        guard let url = request.url, allowedURLs.contains(url.absoluteString),
              request.httpMethod == "POST", request.httpBodyStream == nil,
              let body = request.httpBody, body.count <= Self.maximumBytes else {
            throw PushRegistrationFailure.invalidResponse
        }
        var request = request
        request.timeoutInterval = Self.timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        let result = try await RequestOperation(request: request, protocolClasses: protocolClasses,
            awaitPhysicalCompletion: awaitPhysicalCompletion).value()
        try Task.checkCancellation()
        return result
    }

    static func configuration(protocolClasses: [AnyClass]? = nil) -> URLSessionConfiguration {
        let result = URLSessionConfiguration.ephemeral
        result.httpCookieStorage = nil
        result.httpShouldSetCookies = false
        result.httpCookieAcceptPolicy = .never
        result.urlCredentialStorage = nil
        result.urlCache = nil
        result.requestCachePolicy = .reloadIgnoringLocalCacheData
        result.timeoutIntervalForRequest = timeout
        result.timeoutIntervalForResource = timeout
        result.waitsForConnectivity = false
        result.httpMaximumConnectionsPerHost = 1
        if let protocolClasses { result.protocolClasses = protocolClasses }
        return result
    }

    private static func validEndpoint(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              !parts.path.isEmpty, parts.path != "/", !host.contains("%"),
              parts.port.map({ (1...65_535).contains($0) }) ?? true else { return false }
        return true
    }

    /// The lock owns setup and termination as well as the accumulator. A
    /// cancelled caller may arrive before its continuation or session exists.
    /// URLSession retains this delegate only until the session invalidates.
    final class RequestOperation: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        /// Local transport seam. Like URLSessionTask.resume/cancel, these effects
        /// schedule delegate callbacks asynchronously; they do not call inline.
        struct Lifecycle: Sendable {
            let resume: @Sendable () -> Void
            let cancel: @Sendable () -> Void
        }
        private typealias Output = (Data, HTTPURLResponse)
        private let lock = NSLock()
        private let request: URLRequest
        private let protocolClasses: [AnyClass]?
        private let awaitPhysicalCompletion: Bool
        private let lifecycle: Lifecycle?
        private var physicallyStarted = false
        private var physicallyCompleted = false
        private var finished = false
        private var continuation: CheckedContinuation<Output, Error>?
        private var terminal: Result<Output, Error>?
        private var session: URLSession?
        private var task: URLSessionDataTask?
        private var deadline: DispatchSourceTimer?
        private var response: HTTPURLResponse?
        private var data = Data()

        init(request: URLRequest, protocolClasses: [AnyClass]? = nil, awaitPhysicalCompletion: Bool = false,
             lifecycle: Lifecycle? = nil) {
            self.request = request
            self.protocolClasses = protocolClasses
            self.awaitPhysicalCompletion = awaitPhysicalCompletion
            self.lifecycle = lifecycle
        }

        func value() async throws -> (Data, HTTPURLResponse) {
            try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { start($0) }
            }, onCancel: { self.cancel() })
        }

        private func start(_ continuation: CheckedContinuation<Output, Error>) {
            lock.lock()
            if let terminal {
                lock.unlock()
                continuation.resume(with: terminal)
                return
            }
            // A RequestOperation is used once. Keep a misuse bounded as well.
            guard self.continuation == nil else {
                lock.unlock()
                continuation.resume(throwing: PushRegistrationFailure.invalidResponse)
                return
            }
            self.continuation = continuation
            if let lifecycle {
                physicallyStarted = true
                lifecycle.resume()
                lock.unlock()
                return
            }
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration: PushRegistrationURLSessionExecutor.configuration(protocolClasses: protocolClasses),
                                     delegate: self, delegateQueue: queue)
            let task = session.dataTask(with: request)
            let deadline = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
            deadline.setEventHandler { [weak self] in self?.deadlineExpired() }
            deadline.schedule(deadline: .now() + PushRegistrationURLSessionExecutor.timeout)
            self.session = session
            self.task = task
            self.deadline = deadline
            deadline.resume()
            physicallyStarted = true
            task.resume()
            lock.unlock()
        }

        func cancel() { finish(.failure(CancellationError())) }

        // Default callers retain the existing bounded logical completion. The
        // opt-in path cancels but waits for physical delegate acknowledgement.
        func deadlineExpired() { finish(.failure(URLError(.timedOut))) }

        private func finish(_ result: Result<Output, Error>, physicalCompletion: Bool = false) {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            if physicalCompletion { physicallyCompleted = true }
            let first = terminal == nil
            if first { terminal = result }
            guard let accepted = terminal else { lock.unlock(); return }
            if awaitPhysicalCompletion && physicallyStarted && !physicallyCompleted {
                // First cause wins. Stop accumulating bytes immediately, but do
                // not release the caller's physical slot on a logical timeout.
                let task = self.task, session = self.session, deadline = self.deadline
                self.deadline = nil; self.response = nil; self.data.removeAll(keepingCapacity: false)
                lock.unlock()
                if first {
                    deadline?.cancel(); task?.cancel(); session?.invalidateAndCancel(); lifecycle?.cancel()
                }
                return
            }
            finished = true
            let continuation = self.continuation
            let task = self.task
            let session = self.session
            let deadline = self.deadline
            let cancelLifecycle = physicallyStarted && !physicallyCompleted
            self.continuation = nil
            self.task = nil
            self.session = nil
            self.deadline = nil
            self.response = nil
            self.data.removeAll(keepingCapacity: false)
            lock.unlock()
            deadline?.cancel()
            task?.cancel()
            session?.invalidateAndCancel()
            if cancelLifecycle { lifecycle?.cancel() }
            continuation?.resume(with: accepted)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            // Even an allowlisted same-origin redirect is forbidden. The
            // original authenticated body must never be forwarded/replayed.
            if awaitPhysicalCompletion { finish(.failure(PushRegistrationFailure.invalidResponse)) }
            completionHandler(nil)
            if !awaitPhysicalCompletion { finish(.failure(PushRegistrationFailure.invalidResponse)) }
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            lock.lock()
            guard terminal == nil else { lock.unlock(); completionHandler(.cancel); return }
            guard self.response == nil, let http = response as? HTTPURLResponse,
                  http.url?.absoluteString == request.url?.absoluteString,
                  Self.acceptableLength(http) else {
                lock.unlock()
                if awaitPhysicalCompletion { finish(.failure(PushRegistrationFailure.invalidResponse)) }
                completionHandler(.cancel)
                if !awaitPhysicalCompletion { finish(.failure(PushRegistrationFailure.invalidResponse)) }
                return
            }
            self.response = http
            lock.unlock()
            completionHandler(.allow)
        }

        private static func acceptableLength(_ response: HTTPURLResponse) -> Bool {
            let maximum = PushRegistrationURLSessionExecutor.maximumBytes
            guard response.expectedContentLength <= Int64(maximum) else { return false }
            if let raw = response.value(forHTTPHeaderField: "Content-Length") {
                let raw = raw.trimmingCharacters(in: .whitespaces)
                guard !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }),
                      let length = UInt64(raw), length <= UInt64(maximum) else { return false }
            }
            return true
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            lock.lock()
            guard terminal == nil else { lock.unlock(); return }
            guard response != nil,
                  data.count <= PushRegistrationURLSessionExecutor.maximumBytes - self.data.count else {
                lock.unlock()
                finish(.failure(PushRegistrationFailure.invalidResponse))
                return
            }
            self.data.append(data)
            lock.unlock()
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            lock.lock()
            if let terminal { lock.unlock(); finish(terminal, physicalCompletion: true); return }
            if let error { lock.unlock(); finish(.failure(error), physicalCompletion: true); return }
            guard let response else {
                lock.unlock()
                finish(.failure(PushRegistrationFailure.invalidResponse), physicalCompletion: true)
                return
            }
            let result = (data, response)
            lock.unlock()
            finish(.success(result), physicalCompletion: true)
        }

        func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
            finish(.failure(error ?? PushRegistrationFailure.invalidResponse), physicalCompletion: true)
        }

        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            handle(challenge, completionHandler: completionHandler)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            handle(challenge, completionHandler: completionHandler)
        }

        private func handle(_ challenge: URLAuthenticationChallenge,
                            completionHandler: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
                // Keep the operating system's ordinary certificate validation.
                completionHandler(.performDefaultHandling, nil)
            } else {
                if awaitPhysicalCompletion { finish(.failure(PushRegistrationFailure.invalidResponse)) }
                completionHandler(.cancelAuthenticationChallenge, nil)
                if !awaitPhysicalCompletion { finish(.failure(PushRegistrationFailure.invalidResponse)) }
            }
        }
    }
}
