import CoreFoundation
import Foundation

/// Auth-only, explicitly injected transport for one original startup attempt.
/// Construction performs no I/O. Decoding an HTTP reply does not initialise a
/// reader SDK or establish that the separately configured deployment is live.
@MainActor
final class ReaderStartupHTTPTransport {
    typealias Context = CanonicalSessionState.ContextTicket
    typealias MembershipRequest = ReaderAuthoritativeReadContract.MembershipRequest
    typealias MembershipSnapshot = ReaderAuthoritativeReadContract.MembershipSnapshot
    typealias Challenge = ReaderStartupCoordinator.Challenge
    typealias Permit = ReaderStartupCoordinator.Permit
    enum Failure: Error, Equatable {
        case invalidConfiguration, invalidRequest, invalidCredentials, invalidResponse, stale, expired, alreadyUsed
    }
    struct Configuration: Equatable, Sendable {
        let startup: ReaderStartupCoordinator.Configuration
        let membershipURL: URL
        let attestationURL: URL
        let deploymentEvidenceSHA256: String
        init(startup: ReaderStartupCoordinator.Configuration, membershipURL: URL, attestationURL: URL,
             deploymentEvidenceSHA256: String) throws {
            // This existing executor initializer validates exact HTTPS URLs;
            // it constructs neither URLSession nor a network operation.
            do { _ = try PushRegistrationURLSessionExecutor(allowedURLs: [membershipURL, attestationURL]) }
            catch { throw Failure.invalidConfiguration }
            guard membershipURL.absoluteString != attestationURL.absoluteString,
                  let a = URLComponents(url: membershipURL, resolvingAgainstBaseURL: false),
                  let b = URLComponents(url: attestationURL, resolvingAgainstBaseURL: false),
                  a.host?.lowercased() == b.host?.lowercased(), (a.port ?? 443) == (b.port ?? 443),
                  Self.validText(startup.projectID), Self.validText(startup.appID),
                  ReaderStartupHTTPTransport.validHash(deploymentEvidenceSHA256) else { throw Failure.invalidConfiguration }
            self.startup = startup; self.membershipURL = membershipURL; self.attestationURL = attestationURL
            self.deploymentEvidenceSHA256 = deploymentEvidenceSHA256
        }
        private static func validText(_ value: String) -> Bool {
            (1...256).contains(value.utf8.count) && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
                && !value.unicodeScalars.contains { $0.properties.generalCategory == .control || $0.properties.generalCategory == .format }
        }
    }
    struct Credentials: Sendable {
        let ownerUID: String
        let projectID: String
        let appID: String
        let idToken: String
        let appCheckToken: String
        let authValidUntilMs: Int64
        let appCheckValidUntilMs: Int64
    }

    private enum Phase { case fresh, membership, ready, attestation, complete }
    private let configuration: Configuration
    private let context: Context
    private let credentials: @MainActor (Context) async throws -> Credentials
    private let isCurrent: @MainActor (Context) -> Bool
    private let execute: @MainActor (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let now: @MainActor () -> Int64
    private var phase = Phase.fresh
    private var denied = false
    private var membership: MembershipSnapshot?
    private var membershipCredentialExpiry: Int64?
    private static let maximumBytes = 16_384
    private static let maximumAttestationLifetimeMs: Int64 = 60_000
    nonisolated private static let maximumSafeInteger: Int64 = 9_007_199_254_740_991

    init(configuration: Configuration, context: Context,
         credentials: @escaping @MainActor (Context) async throws -> Credentials,
         isCurrent: @escaping @MainActor (Context) -> Bool,
         execute: @escaping @MainActor (URLRequest) async throws -> (Data, HTTPURLResponse),
         now: @escaping @MainActor () -> Int64) {
        self.configuration = configuration; self.context = context; self.credentials = credentials
        self.isCurrent = isCurrent; self.execute = execute; self.now = now
    }

    func readMembership(_ request: MembershipRequest) async throws -> MembershipSnapshot {
        guard phase == .fresh else { throw Failure.alreadyUsed }
        phase = .membership // Reserve before injected identity/credential hooks.
        do {
            try check()
            guard request.expectedUID == context.userID else { throw Failure.invalidRequest }
            let body = try ReaderAuthoritativeReadContract.encode(request)
            let tokens = try await credentials(context)
            try check()
            let expiry = try credentialExpiry(tokens)
            _ = try fresh(until: expiry)
            let (data, response) = try await execute(http(configuration.membershipURL, body: body, tokens: tokens))
            try check()
            _ = try fresh(until: expiry)
            try validateHTTP(data, response: response, endpoint: configuration.membershipURL)
            let result = try ReaderAuthoritativeReadContract.decodeMembershipResponse(data: data, for: request)
            guard result.validUntilMs <= expiry else { throw Failure.invalidResponse }
            _ = try fresh(until: result.validUntilMs)
            try check()
            membership = result; membershipCredentialExpiry = expiry; phase = .ready
            return result
        } catch { denied = true; phase = .complete; throw error }
    }

    func verify(_ challenge: Challenge) async throws -> Permit {
        guard phase == .ready else { throw Failure.alreadyUsed }
        phase = .attestation
        do {
            try check()
            guard let membership, let firstExpiry = membershipCredentialExpiry,
                  let member = membership.membership, member.state == .active,
                  challenge.context == context, challenge.configuration == configuration.startup,
                  challenge.binding == member.binding, challenge.binding.ownerUID == context.userID,
                  challenge.readID == membership.request.readID,
                  challenge.marker.map({ $0.binding == challenge.binding }) ?? true else { throw Failure.invalidRequest }
            let priorExpiry = min(membership.validUntilMs, firstExpiry)
            _ = try fresh(until: priorExpiry)
            let body = try challengeData(challenge)
            let tokens = try await credentials(context)
            try check()
            let secondExpiry = try credentialExpiry(tokens)
            let validUntil = min(priorExpiry, secondExpiry)
            let sentAt = try fresh(until: validUntil)
            let (data, response) = try await execute(http(configuration.attestationURL, body: body, tokens: tokens))
            try check()
            _ = try fresh(until: validUntil)
            try validateHTTP(data, response: response, endpoint: configuration.attestationURL)
            let expiry = try attestationExpiry(data, original: body)
            guard expiry <= secondExpiry else { throw Failure.invalidResponse }
            // The server may obtain fresh evidence after processing starts.
            // Its legitimate expiry can exceed send-time + 60s. Shorten our
            // local permit instead of rejecting that reply or extending trust.
            let permitExpiry = min(validUntil, expiry, sentAt + Self.maximumAttestationLifetimeMs)
            _ = try fresh(until: permitExpiry)
            try check()
            phase = .complete
            return Permit(challenge: challenge, coverage: .allPersistedWritersIncludingPreviousAccounts,
                writerFenceRevision: configuration.startup.writerFenceRevision,
                migrationRevision: configuration.startup.migrationRevision, validUntilMs: permitExpiry)
        } catch { denied = true; phase = .complete; throw error }
    }

    private func check() throws {
        guard !denied else { throw Failure.stale }
        if Task.isCancelled { denied = true; throw CancellationError() }
        let accepted = isCurrent(context)
        guard accepted, !denied, !Task.isCancelled else { denied = true; throw Failure.stale }
    }
    private func fresh(until: Int64) throws -> Int64 {
        try check()
        let time = now()
        try check() // A clock is injected code too; it may replace the account.
        guard Self.positiveSafe(time), Self.positiveSafe(until), time < until else { throw Failure.expired }
        return time
    }
    private func credentialExpiry(_ value: Credentials) throws -> Int64 {
        try check()
        guard value.ownerUID == context.userID,
              Data(value.projectID.utf8) == Data(configuration.startup.projectID.utf8),
              Data(value.appID.utf8) == Data(configuration.startup.appID.utf8),
              Self.validToken(value.idToken), Self.validToken(value.appCheckToken),
              Self.positiveSafe(value.authValidUntilMs), Self.positiveSafe(value.appCheckValidUntilMs) else { throw Failure.invalidCredentials }
        return min(value.authValidUntilMs, value.appCheckValidUntilMs)
    }
    private func http(_ url: URL, body: Data, tokens: Credentials) throws -> URLRequest {
        try check()
        guard !body.isEmpty, body.count <= 8_192 else { throw Failure.invalidRequest }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: PushRegistrationURLSessionExecutor.timeout)
        request.httpMethod = "POST"; request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer " + tokens.idToken, forHTTPHeaderField: "Authorization")
        request.setValue(tokens.appCheckToken, forHTTPHeaderField: "X-Firebase-AppCheck")
        request.httpBody = body
        return request
    }
    private func validateHTTP(_ data: Data, response: HTTPURLResponse, endpoint: URL) throws {
        guard response.statusCode == 200, response.url?.absoluteString == endpoint.absoluteString,
              response.mimeType?.lowercased() == "application/json", !data.isEmpty, data.count <= Self.maximumBytes,
              response.expectedContentLength <= Self.maximumBytes else { throw Failure.invalidResponse }
        if let length = response.value(forHTTPHeaderField: "Content-Length") {
            let raw = length.trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }),
                  let parsed = Int64(raw), parsed <= Self.maximumBytes else { throw Failure.invalidResponse }
        }
    }
    private func challengeData(_ value: Challenge) throws -> Data {
        let c = value.configuration
        let bind: [String: Any] = ["ownerUID": value.binding.ownerUID, "epoch": value.binding.epoch]
        let marker: Any
        if let value = value.marker { marker = ["binding": bind, "transitionID": value.transitionID.uuidString.lowercased()] }
        else { marker = NSNull() }
        let object: [String: Any] = ["schemaVersion": 1,
            "configuration": ["projectID": c.projectID, "appID": c.appID, "installationID": c.installationID.uuidString.lowercased(),
                "writerFenceRevision": c.writerFenceRevision, "migrationRevision": c.migrationRevision],
            "context": ["userID": value.binding.ownerUID, "generation": context.generation.uuidString.lowercased()],
            "binding": bind, "marker": marker, "readID": value.readID]
        return try Self.canonical(object)
    }
    private func attestationExpiry(_ data: Data, original: Data) throws -> Int64 {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["schemaVersion", "scope", "request", "coverage", "deploymentEvidenceSHA256", "validUntilMs"],
              Self.integer(object["schemaVersion"]) == 1,
              object["scope"] as? String == "reader-startup-attestation-v1",
              object["coverage"] as? String == "all_persisted_writers_including_previous_accounts",
              object["deploymentEvidenceSHA256"] as? String == configuration.deploymentEvidenceSHA256,
              let request = object["request"] as? [String: Any],
              Self.integer(request["schemaVersion"]) == 1,
              let binding = request["binding"] as? [String: Any], Self.integer(binding["epoch"]) != nil,
              let expiry = Self.integer(object["validUntilMs"]), Self.positiveSafe(expiry),
              try Self.canonical(request) == original else { throw Failure.invalidResponse }
        // Full canonical echo includes keys, null marker, UUID casing and exact
        // UTF-8 text. JSON booleans may not stand in for schema/epoch numbers.
        if let marker = request["marker"] as? [String: Any] {
            guard let binding = marker["binding"] as? [String: Any], Self.integer(binding["epoch"]) != nil else { throw Failure.invalidResponse }
        }
        return expiry
    }
    nonisolated private static func canonical(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    nonisolated private static func integer(_ raw: Any?) -> Int64? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded(.towardZero) == number.doubleValue,
              number.doubleValue >= 0, number.doubleValue <= Double(maximumSafeInteger) else { return nil }
        return number.int64Value
    }
    nonisolated private static func positiveSafe(_ value: Int64) -> Bool { (1...maximumSafeInteger).contains(value) }
    nonisolated private static func validHash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    nonisolated private static func validToken(_ value: String) -> Bool {
        (1...16_384).contains(value.utf8.count) && value.utf8.allSatisfy { (33...126).contains($0) }
    }
}
