import Foundation

/// One explicitly confirmed, originally bound deletion phase. Construction is
/// inert; a valid HTTP receipt never means the whole account has been deleted.
@MainActor
final class ReaderDeletionHTTPTransport {
    typealias Contract = ReaderAccountDeletionContract
    typealias Coordinator = ReaderAccountDeletionCoordinator
    enum Failure: Error, Equatable {
        case invalidConfiguration, invalidRequest, invalidCredentials, invalidResponse, stale, expired, alreadyUsed
    }
    struct Configuration: Equatable, Sendable {
        let projectID: String
        let appID: String
        let endpointURL: URL
        init(projectID: String, appID: String, endpointURL: URL) throws {
            do { _ = try PushRegistrationURLSessionExecutor(allowedURLs: [endpointURL]) }
            catch { throw Failure.invalidConfiguration }
            guard projectID.range(of: "\\A[a-z][a-z0-9-]{4,28}[a-z0-9]\\z", options: .regularExpression) != nil,
                  appID.range(of: "\\A1:[0-9]{6,30}:ios:[a-f0-9]{6,64}\\z", options: .regularExpression) != nil else {
                throw Failure.invalidConfiguration
            }
            self.projectID = projectID; self.appID = appID; self.endpointURL = endpointURL
        }
    }
    struct Credentials: Sendable {
        let ownerUID: String
        let projectID: String
        let appID: String
        let idToken: String
        let appCheckToken: String
        let authTimeMs: Int64
        let authValidUntilMs: Int64
        let appCheckValidUntilMs: Int64
    }
    private let configuration: Configuration
    private let action: Coordinator.ActionTicket
    private let proof: Coordinator.ReauthenticationResult
    private let credentials: @MainActor (@escaping @MainActor () -> Bool) async throws -> Credentials
    private let isCurrent: @MainActor () -> Bool
    private let execute: @MainActor (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let now: @MainActor () -> Int64
    private let validateOriginal: (@MainActor () async throws -> Void)?
    private var used = false
    private var denied = false
    private var finished = false
    nonisolated private static let maximumSafeInteger: Int64 = 9_007_199_254_740_991

    init(configuration: Configuration, action: Coordinator.ActionTicket, proof: Coordinator.ReauthenticationResult,
         credentials: @escaping @MainActor (@escaping @MainActor () -> Bool) async throws -> Credentials,
         isCurrent: @escaping @MainActor () -> Bool,
         execute: @escaping @MainActor (URLRequest) async throws -> (Data, HTTPURLResponse),
         now: @escaping @MainActor () -> Int64,
         validateOriginal: (@MainActor () async throws -> Void)? = nil) {
        self.configuration = configuration; self.action = action; self.proof = proof
        self.credentials = credentials; self.isCurrent = isCurrent; self.execute = execute; self.now = now
        self.validateOriginal = validateOriginal
    }

    func send(_ request: Contract.Request) async throws -> Data {
        try reserve()
        do {
            try checkProof()
            guard action.phase == .cloudSlice, action.ledgerRequest == nil, action.request == request else {
                throw Failure.invalidRequest
            }
            return try await perform(encoded(request)) { _ = try Contract.decodeReceipt(data: $0, for: request) }
        } catch { denied = true; finished = true; throw error }
    }

    func sendLedger(_ request: Contract.LedgerRequest) async throws -> Data {
        try reserve()
        do {
            try checkProof()
            guard action.phase == .mutationLedger, action.ledgerRequest == request,
                  request.expectedUID == action.request.expectedUID,
                  request.membershipEpoch == action.request.membershipEpoch,
                  request.parentRequestID == action.request.requestID else { throw Failure.invalidRequest }
            return try await perform(encoded(request)) { _ = try Contract.decodeLedgerReceipt(data: $0, for: request) }
        } catch { denied = true; finished = true; throw error }
    }

    func sendPushPreparation(_ request: Contract.PushRequest) async throws -> Data {
        try reserve()
        do {
            try checkProof()
            try checkPush(request, phase: .pushPreparation, scope: Contract.pushPreparationScope)
            return try await perform(encoded(request)) {
                _ = try Contract.decodePushPreparationReceipt(data: $0, for: request, appID: configuration.appID)
            }
        } catch { denied = true; finished = true; throw error }
    }

    func sendPushRetirement(_ request: Contract.PushRequest) async throws -> Data {
        try reserve()
        do {
            try checkProof()
            try checkPush(request, phase: .pushRetirement, scope: Contract.pushScope)
            guard request.installation.snapshot?.appId == configuration.appID else { throw Failure.invalidRequest }
            return try await perform(encoded(request)) {
                _ = try Contract.decodePushReceipt(data: $0, for: request, appID: configuration.appID)
            }
        } catch { denied = true; finished = true; throw error }
    }

    private func checkPush(_ request: Contract.PushRequest, phase: Coordinator.Phase, scope: String) throws {
        guard action.phase == phase, action.pushRequest == request, request.scope == scope,
              request.expectedUID == action.request.expectedUID, request.membershipEpoch == action.request.membershipEpoch,
              request.parentRequestID == action.request.requestID else { throw Failure.invalidRequest }
    }

    private func reserve() throws {
        guard !used else { throw Failure.alreadyUsed }
        used = true // Reserve synchronously before any injected clock/identity hook.
    }
    private func perform(_ body: Data, validate: (Data) throws -> Void) async throws -> Data {
        guard !body.isEmpty, body.count <= 8_192 else { throw Failure.invalidRequest }
        try await validateOriginalBinding(until: nil)
        let tokens = try await credentials { [weak self] in self?.stillAdmitted() == true }
        try checkProof()
        let expiry = try credentialExpiry(tokens)
        try fresh(until: expiry)
        var request = URLRequest(url: configuration.endpointURL, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: PushRegistrationURLSessionExecutor.timeout)
        request.httpMethod = "POST"; request.httpShouldHandleCookies = false; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer " + tokens.idToken, forHTTPHeaderField: "Authorization")
        request.setValue(tokens.appCheckToken, forHTTPHeaderField: "X-Firebase-AppCheck")
        try fresh(until: expiry)
        try await validateOriginalBinding(until: expiry)
        let (data, response) = try await execute(request)
        try fresh(until: expiry)
        try await validateOriginalBinding(until: expiry)
        try validateHTTP(data, response: response)
        try validate(data)
        try fresh(until: expiry)
        finished = true
        return data
    }
    private func validateOriginalBinding(until expiry: Int64?) async throws {
        guard let validateOriginal else { return }
        if let expiry { try fresh(until: expiry) } else { try checkProof() }
        try await validateOriginal()
        if let expiry { try fresh(until: expiry) } else { try checkProof() }
    }
    private func stillAdmitted() -> Bool {
        do { try checkProof(); return true }
        catch { denied = true; return false }
    }
    private func check() throws {
        guard !denied, !finished else { throw Failure.stale }
        if Task.isCancelled { denied = true; throw CancellationError() }
        let accepted = isCurrent()
        guard accepted, !denied, !Task.isCancelled else { denied = true; throw Failure.stale }
    }
    @discardableResult
    private func checkProof() throws -> Int64 {
        try check()
        guard proof.action == action, proof.kind == .reauthenticated,
              action.context.userID == action.request.expectedUID,
              proof.authenticatedUID == action.request.expectedUID,
              Self.positiveSafe(action.startedAtMs), Self.positiveSafe(proof.authTimeMs),
              proof.authTimeMs % 1_000 == 0 else { throw Failure.invalidCredentials }
        let time = now()
        try check() // A clock hook may replace the original account as well.
        let earliest = (action.startedAtMs / 1_000) * 1_000
        guard Self.positiveSafe(time), time >= action.startedAtMs,
              proof.authTimeMs >= earliest, proof.authTimeMs <= time,
              time - action.startedAtMs < 300_000, time - proof.authTimeMs < 300_000 else { throw Failure.expired }
        return time
    }
    private func fresh(until expiry: Int64) throws {
        let time = try checkProof()
        guard Self.positiveSafe(time), Self.positiveSafe(expiry), time < expiry else { throw Failure.expired }
    }
    private func credentialExpiry(_ value: Credentials) throws -> Int64 {
        try checkProof()
        guard value.ownerUID == action.request.expectedUID, value.authTimeMs == proof.authTimeMs,
              Data(value.projectID.utf8) == Data(configuration.projectID.utf8),
              Data(value.appID.utf8) == Data(configuration.appID.utf8),
              Self.validToken(value.idToken), Self.validToken(value.appCheckToken),
              Self.positiveSafe(value.authValidUntilMs), Self.positiveSafe(value.appCheckValidUntilMs),
              proof.authTimeMs <= Self.maximumSafeInteger - 300_000,
              action.startedAtMs <= Self.maximumSafeInteger - 300_000 else { throw Failure.invalidCredentials }
        return min(value.authValidUntilMs, value.appCheckValidUntilMs, proof.authTimeMs + 300_000, action.startedAtMs + 300_000)
    }
    private func validateHTTP(_ data: Data, response: HTTPURLResponse) throws {
        guard response.statusCode == 200, response.url?.absoluteString == configuration.endpointURL.absoluteString,
              response.mimeType?.lowercased() == "application/json", !data.isEmpty, data.count <= 16_384,
              response.expectedContentLength <= 16_384 else { throw Failure.invalidResponse }
        if let length = response.value(forHTTPHeaderField: "Content-Length") {
            let raw = length.trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }),
                  let parsed = Int64(raw), parsed <= 16_384 else { throw Failure.invalidResponse }
        }
    }
    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    nonisolated private static func positiveSafe(_ value: Int64) -> Bool { (1...maximumSafeInteger).contains(value) }
    nonisolated private static func validToken(_ value: String) -> Bool {
        (1...8_192).contains(value.utf8.count) && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95 || $0 == 45 || $0 == 46
        }
    }
}
