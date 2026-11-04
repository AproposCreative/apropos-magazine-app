import Foundation

/// Explicit foreground download transport. Construction opens no session. Body
/// chunks go to one private staging file, never an accumulated in-memory body.
enum PodcastAudioDownloadTransport {
    enum Failure: Error { case invalidResponse }
    typealias Output = (temporaryURL: URL, response: HTTPURLResponse)
    typealias Progress = @Sendable (_ receivedBytes: Int64, _ expectedBytes: Int64?) -> Void
    static let timeout: TimeInterval = 180
    static let hardMaximumBytes: Int64 = 256 * 1024 * 1024

    static func download(from url: URL, maximumBytes: Int64, onProgress: @escaping Progress = { _, _ in }) async throws -> Output {
        try Task.checkCancellation()
        let result = try await RequestOperation(url: url, maximumBytes: maximumBytes, onProgress: onProgress).value()
        if Task.isCancelled {
            try? FileManager.default.removeItem(at: result.temporaryURL)
            throw CancellationError()
        }
        return result
    }

    static func configuration(protocolClasses: [AnyClass]? = nil) -> URLSessionConfiguration {
        let value = URLSessionConfiguration.ephemeral
        value.urlCache = nil; value.urlCredentialStorage = nil; value.httpCookieStorage = nil
        value.httpShouldSetCookies = false; value.httpCookieAcceptPolicy = .never
        value.requestCachePolicy = .reloadIgnoringLocalCacheData
        value.timeoutIntervalForRequest = 30; value.timeoutIntervalForResource = timeout
        value.waitsForConnectivity = false; value.httpMaximumConnectionsPerHost = 1
        if let protocolClasses { value.protocolClasses = protocolClasses }
        return value
    }

    private static func validURL(_ url: URL) -> Bool {
        guard url.absoluteString.utf8.count <= 4096,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", parts.user == nil, parts.password == nil,
              parts.fragment == nil, parts.host?.isEmpty == false,
              url.pathExtension.lowercased() != "m3u8" else { return false }
        return PodcastAudioURLValidator.isPlayableAudioURL(url)
    }

    /// All state and file operations belong to control. Cancel enqueues work,
    /// so a UI caller never waits on file I/O. An active caller resumes only
    /// after URLSession confirms invalidation and every task has retired.
    final class RequestOperation: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let control = DispatchQueue(label: "com.aproposmagazine.audio-download", qos: .utility)
        private let url: URL
        private let maximumBytes: Int64
        private let protocolClasses: [AnyClass]?
        private let temporaryDirectory: URL
        private let onProgress: Progress
        private var used = false
        private var delivered = false
        private var continuation: CheckedContinuation<Output, Error>?
        private var result: Result<Output, Error>?
        private var session: URLSession?
        private var task: URLSessionDataTask?
        private var deadline: DispatchSourceTimer?
        private var response: HTTPURLResponse?
        private var file: URL?
        private var handle: FileHandle?
        private var received: Int64 = 0
        private var redirects = 0
        private var expectedURL: URL

        init(url: URL, maximumBytes: Int64, protocolClasses: [AnyClass]? = nil,
             temporaryDirectory: URL = FileManager.default.temporaryDirectory, onProgress: @escaping Progress = { _, _ in }) {
            self.url = url; self.maximumBytes = maximumBytes
            self.expectedURL = url
            self.protocolClasses = protocolClasses; self.temporaryDirectory = temporaryDirectory
            self.onProgress = onProgress
        }

        func value() async throws -> Output {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    control.async { self.start(continuation) }
                }
            } onCancel: { self.cancel() }
        }
        func cancel() { control.async { self.fail(CancellationError()) } }
        func deadlineExpired() { control.async { self.fail(URLError(.timedOut)) } }

        private func start(_ continuation: CheckedContinuation<Output, Error>) {
            guard !used else { continuation.resume(throwing: Failure.invalidResponse); return }
            used = true; self.continuation = continuation
            if result != nil { finishInvalidation(); return }
            guard validURL(url), (1...hardMaximumBytes).contains(maximumBytes) else {
                fail(Failure.invalidResponse); return
            }
            do {
                let file = temporaryDirectory.appendingPathComponent(UUID().uuidString + ".audio-download")
                guard FileManager.default.createFile(atPath: file.path, contents: nil) else { throw Failure.invalidResponse }
                self.file = file; handle = try FileHandle(forWritingTo: file)
                let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1; queue.underlyingQueue = control
                let session = URLSession(configuration: configuration(protocolClasses: protocolClasses), delegate: self, delegateQueue: queue)
                var request = URLRequest(url: url)
                request.httpShouldHandleCookies = false; request.cachePolicy = .reloadIgnoringLocalCacheData
                request.timeoutInterval = 30; request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                let task = session.dataTask(with: request)
                let deadline = DispatchSource.makeTimerSource(queue: control)
                deadline.setEventHandler { [weak self] in self?.fail(URLError(.timedOut)) }
                deadline.schedule(deadline: .now() + timeout)
                self.session = session; self.task = task; self.deadline = deadline
                deadline.resume(); task.resume()
            } catch { fail(error) }
        }

        private func fail(_ error: Error) {
            guard !delivered else { return }
            if case .failure? = result { return }
            result = .failure(error)
            try? handle?.close(); handle = nil
            if let file { try? FileManager.default.removeItem(at: file) }
            file = nil
            deadline?.cancel(); deadline = nil
            if let session { task?.cancel(); session.invalidateAndCancel() }
            else { finishInvalidation() }
        }
        private func finishInvalidation() {
            deadline?.cancel(); deadline = nil
            session = nil; task = nil; response = nil
            guard let continuation, let result else { return }
            self.continuation = nil
            delivered = true
            continuation.resume(with: result)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            let reply = Reply(completionHandler)
            control.async {
                guard self.session === session, self.task === task, self.result == nil else { reply.call(nil); return }
                guard self.redirects < 3, let url = request.url, validURL(url) else {
                    reply.call(nil); self.fail(Failure.invalidResponse); return
                }
                self.redirects += 1
                self.expectedURL = url
                var next = URLRequest(url: url)
                next.httpShouldHandleCookies = false; next.cachePolicy = .reloadIgnoringLocalCacheData
                next.timeoutInterval = 30; next.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                reply.call(next)
            }
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            let reply = Reply(completionHandler)
            control.async {
                guard self.session === session, self.task === dataTask, self.result == nil else { reply.call(.cancel); return }
                guard self.response == nil, let http = response as? HTTPURLResponse,
                      let url = http.url, url.absoluteString == self.expectedURL.absoluteString,
                      validURL(url), http.statusCode == 200,
                      http.value(forHTTPHeaderField: "Content-Range") == nil,
                      self.accepts(http) else { reply.call(.cancel); self.fail(Failure.invalidResponse); return }
                self.response = http
                self.onProgress(0, http.expectedContentLength > 0 ? http.expectedContentLength : nil)
                reply.call(.allow)
            }
        }
        private func accepts(_ response: HTTPURLResponse) -> Bool {
            guard response.expectedContentLength <= maximumBytes else { return false }
            if let length = response.value(forHTTPHeaderField: "Content-Length") {
                guard !length.isEmpty, length.utf8.allSatisfy({ (48...57).contains($0) }),
                      let value = Int64(length), value <= maximumBytes else { return false }
            }
            if let encoding = response.value(forHTTPHeaderField: "Content-Encoding"), encoding.lowercased() != "identity" { return false }
            if let mime = response.mimeType?.lowercased(),
               !(mime.hasPrefix("audio/") || mime.hasPrefix("video/") || mime == "application/octet-stream") { return false }
            return true
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            control.async {
                guard self.session === session, self.task === dataTask, self.result == nil else { return }
                guard let response = self.response, Int64(data.count) <= self.maximumBytes - self.received, let handle = self.handle else {
                    self.fail(Failure.invalidResponse); return
                }
                do {
                    try handle.write(contentsOf: data); self.received += Int64(data.count)
                    let total = response.expectedContentLength
                    if total <= 0 || self.received <= total { self.onProgress(self.received, total > 0 ? total : nil) }
                }
                catch { self.fail(error) }
            }
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            control.async {
                guard self.session === session, self.task === task else { return }
                if let error { self.fail(error); return }
                guard self.result == nil else { return }
                guard let response = self.response, let file = self.file, self.received > 0,
                      response.expectedContentLength < 0 || response.expectedContentLength == self.received else {
                    self.fail(Failure.invalidResponse); return
                }
                do { try self.handle?.close(); self.handle = nil }
                catch { self.fail(error); return }
                self.result = .success((file, response))
                session.finishTasksAndInvalidate()
            }
        }
        func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
            control.async {
                guard self.session === session else { return }
                if self.result == nil { self.fail(error ?? URLError(.cancelled)) }
                self.finishInvalidation()
            }
        }
        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
                completionHandler(.performDefaultHandling, nil)
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                control.async { if self.session === session { self.fail(Failure.invalidResponse) } }
            }
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            // Both task- and session-level challenges reject ambient accounts.
            urlSession(session, didReceive: challenge, completionHandler: completionHandler)
        }
        private final class Reply<Value>: @unchecked Sendable {
            private let action: (Value) -> Void
            init(_ action: @escaping (Value) -> Void) { self.action = action }
            func call(_ value: Value) { action(value) }
        }
    }
}
