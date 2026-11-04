import CoreFoundation
import Foundation

struct PushRegistrationCredentials: Equatable, Sendable {
    let appCheckToken: String
    let idToken: String?
    let ownerUID: String?
}

/// An unconfigured transport: construction performs no network or SDK work.
/// Before service activation, `perform` must be supplied by an ephemeral session
/// that refuses redirects. Checking the returned URL cannot undo credentials
/// forwarded by an incorrectly configured session.
@MainActor
struct PushRegistrationHTTPTransport {
    private let expectedAppID: String?
    private let registerURL: URL
    private let confirmURL: URL
    private let credentials: (PushAccountContext) async throws -> PushRegistrationCredentials
    private let isCurrent: (PushRegistrationTicket) -> Bool
    private let perform: (URLRequest) async throws -> (Data, HTTPURLResponse)
    private static let maximumBytes = 16_384

    init(registerURL: URL, confirmURL: URL, expectedAppID: String? = nil,
         credentials: @escaping (PushAccountContext) async throws -> PushRegistrationCredentials,
         isCurrent: @escaping (PushRegistrationTicket) -> Bool,
         perform: @escaping (URLRequest) async throws -> (Data, HTTPURLResponse)) throws {
        guard Self.validEndpoint(registerURL), Self.validEndpoint(confirmURL),
              registerURL.host?.lowercased() == confirmURL.host?.lowercased(),
              registerURL.port == confirmURL.port, registerURL != confirmURL else {
            throw PushRegistrationFailure.invalidResponse
        }
        if let expectedAppID {
            guard !expectedAppID.isEmpty, expectedAppID.utf8.count <= 256,
                  expectedAppID.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { throw PushRegistrationFailure.invalidResponse }
        }
        self.expectedAppID = expectedAppID
        self.registerURL = registerURL
        self.confirmURL = confirmURL
        self.credentials = credentials
        self.isCurrent = isCurrent
        self.perform = perform
    }

    func send(_ call: PushRegistrationCall, ticket: PushRegistrationTicket) async throws -> PushRegistrationReceipt {
        try fence(ticket)
        try Self.validate(call, ticket: ticket)
        let body: Data
        do { body = try call.body() } catch { throw PushRegistrationFailure.invalidResponse }
        guard body.count <= Self.maximumBytes else { throw PushRegistrationFailure.invalidResponse }

        let identity: PushRegistrationCredentials
        do {
            // Limited-use App Check credentials are consumed server-side. Every
            // attempt, including a retry of identical bytes, needs a fresh one.
            identity = try await credentials(ticket.context)
        } catch {
            try fence(ticket)
            if error is CancellationError { throw PushRegistrationFailure.cancelled }
            throw (error as? PushRegistrationFailure) ?? .authentication
        }
        try fence(ticket)
        guard identity.ownerUID == ticket.context.ownerUID,
              Self.validCredential(identity.appCheckToken),
              ticket.context.ownerUID == nil ? identity.idToken == nil : identity.idToken.map(Self.validCredential) == true else {
            throw PushRegistrationFailure.authentication
        }

        let url = call.path == "register" ? registerURL : confirmURL
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(identity.appCheckToken, forHTTPHeaderField: "X-Firebase-AppCheck")
        if let token = identity.idToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if expectedAppID != nil { request.setValue("1", forHTTPHeaderField: "X-Apropos-Push-Binding") }
        request.httpBody = body
        try fence(ticket)

        let data: Data
        let response: HTTPURLResponse
        do { (data, response) = try await perform(request) } catch {
            try fence(ticket)
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw PushRegistrationFailure.cancelled }
            // A bounded executor may reject a redirect, foreign response or
            // oversize stream before any receipt exists. Do not retry policy
            // rejection as a network outage or propagate other injected errors.
            if (error as? PushRegistrationFailure) == .invalidResponse { throw PushRegistrationFailure.invalidResponse }
            throw PushRegistrationFailure.transient(retryAfter: nil)
        }
        try fence(ticket)
        guard response.url?.absoluteString == url.absoluteString, data.count <= Self.maximumBytes else {
            throw PushRegistrationFailure.invalidResponse
        }
        guard response.statusCode == 200 else { throw Self.failure(response, data: data) }
        guard response.value(forHTTPHeaderField: "Content-Type")?.lowercased().split(separator: ";").first?.trimmingCharacters(in: .whitespaces) == "application/json" else {
            throw PushRegistrationFailure.invalidResponse
        }
        return try Self.receipt(data, call: call, ticket: ticket, expectedAppID: expectedAppID)
    }

    private func fence(_ ticket: PushRegistrationTicket) throws {
        guard !Task.isCancelled, isCurrent(ticket) else { throw PushRegistrationFailure.cancelled }
    }

    private static func validEndpoint(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              !parts.path.isEmpty, parts.path != "/", !host.contains("%"),
              parts.port.map({ (1...65_535).contains($0) }) ?? true else { return false }
        return true
    }

    private static func validCredential(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 8_192 && PushRegistrationValidation.matches(value, "^[a-zA-Z0-9_.-]+$")
    }

    private static func validate(_ call: PushRegistrationCall, ticket: PushRegistrationTicket) throws {
        guard ticket.context.isValid else { throw PushRegistrationFailure.authentication }
        guard PushRegistrationValidation.validID(ticket.installationId), validRevision(ticket.clientRevision) else {
            throw PushRegistrationFailure.invalidResponse
        }
        switch call {
        case .register(let value):
            guard value.installationId == ticket.installationId, value.clientRevision == ticket.clientRevision,
                  PushRegistrationValidation.validPrivateValue(value.key) else { throw PushRegistrationFailure.invalidResponse }
            let normalized = try PushRegistrationIntent(context: ticket.context, permission: value.permission,
                preferences: value.preferences, token: value.token).normalized()
            guard normalized.preferences == value.preferences, normalized.token == value.token else { throw PushRegistrationFailure.invalidResponse }
        case .confirm(let value):
            guard value.installationId == ticket.installationId, PushRegistrationValidation.validPrivateValue(value.key),
                  PushRegistrationValidation.validHash(value.challengeId), PushRegistrationValidation.validPrivateValue(value.nonce) else {
                throw PushRegistrationFailure.invalidResponse
            }
        }
    }

    private static func validRevision(_ value: Int64) -> Bool {
        value > 0 && value <= PushRegistrationValidation.maximumRevision
    }

    private static func revision(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
              number.doubleValue >= 1, number.doubleValue <= Double(PushRegistrationValidation.maximumRevision) else { return nil }
        let result = number.int64Value
        return validRevision(result) ? result : nil
    }

    private static func receipt(_ data: Data, call: PushRegistrationCall, ticket: PushRegistrationTicket, expectedAppID: String?) throws -> PushRegistrationReceipt {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: Set(["status", "installationId", "clientRevision", "revision", "challengeId"] + (expectedAppID == nil ? [] : ["binding"]))),
              let statusString = object["status"] as? String, let status = PushRegistrationReceipt.Status(rawValue: statusString),
              object["installationId"] as? String == ticket.installationId,
              revision(object["clientRevision"]) == ticket.clientRevision else { throw PushRegistrationFailure.invalidResponse }
        let serverRevision = revision(object["revision"])
        if let value = object["revision"], !(value is NSNull), serverRevision == nil { throw PushRegistrationFailure.invalidResponse }
        let challenge = object["challengeId"] as? String
        if let value = object["challengeId"], !(value is NSNull), challenge == nil { throw PushRegistrationFailure.invalidResponse }
        switch status {
        case .pending:
            guard case .register(let request) = call, request.permission,
                  request.preferences.articles != .off || request.preferences.podcasts,
                  let challenge, PushRegistrationValidation.validHash(challenge) else { throw PushRegistrationFailure.invalidResponse }
        case .active, .disabled:
            guard serverRevision != nil, challenge == nil else { throw PushRegistrationFailure.invalidResponse }
            switch call {
            case .confirm:
                guard status == .active else { throw PushRegistrationFailure.invalidResponse }
            case .register(let request):
                let enabled = request.permission && (request.preferences.articles != .off || request.preferences.podcasts)
                guard status == (enabled ? .active : .disabled) else { throw PushRegistrationFailure.invalidResponse }
            }
        }
        let binding: PushAcknowledgedInstallationBinding?
        if let expectedAppID {
            guard let value = object["binding"] as? [String: Any],
                  Set(value.keys) == ["schemaVersion", "installationId", "appId", "ownerUID", "ownerEpoch", "revision", "clientRevision", "status"],
                  revision(value["schemaVersion"]) == 1,
                  let ownerEpoch = revision(value["ownerEpoch"]), let boundRevision = revision(value["revision"]),
                  let clientRevision = revision(value["clientRevision"]), let appId = value["appId"] as? String,
                  let installationId = value["installationId"] as? String,
                  let statusRaw = value["status"] as? String, let boundStatus = PushRegistrationReceipt.Status(rawValue: statusRaw),
                  value["ownerUID"] is NSNull || value["ownerUID"] is String else { throw PushRegistrationFailure.invalidResponse }
            let decoded = PushAcknowledgedInstallationBinding(schemaVersion: 1, installationId: installationId, appId: appId,
                ownerUID: value["ownerUID"] as? String, ownerEpoch: ownerEpoch, revision: boundRevision,
                clientRevision: clientRevision, status: boundStatus)
            let legacy = PushRegistrationReceipt(status: status, installationId: ticket.installationId,
                clientRevision: ticket.clientRevision, revision: serverRevision, challengeId: challenge)
            guard decoded.matches(legacy, ticket: ticket, expectedAppID: expectedAppID) else { throw PushRegistrationFailure.invalidResponse }
            binding = decoded
        } else { binding = nil }
        return .init(status: status, installationId: ticket.installationId, clientRevision: ticket.clientRevision,
                     revision: serverRevision, challengeId: challenge, binding: binding)
    }

    private static func failure(_ response: HTTPURLResponse, data: Data) -> PushRegistrationFailure {
        // A proxy can return a non-JSON outage page. HTTP authentication and
        // conflict statuses still block; infrastructure failures remain retryable.
        switch response.statusCode {
        case 401: return .authentication
        case 403: return .forbidden
        case 409: return .conflict
        case 429: return .transient(retryAfter: retryAfter(response.value(forHTTPHeaderField: "Retry-After")))
        case 500...599: return .transient(retryAfter: retryAfter(response.value(forHTTPHeaderField: "Retry-After")))
        default: return .invalidResponse
        }
    }

    private static func retryAfter(_ raw: String?) -> TimeInterval? {
        guard let raw, raw.utf8.count <= 128 else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if PushRegistrationValidation.matches(value, "^[0-9]{1,10}$"), let seconds = Double(value) {
            return min(seconds, 86_400)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else { return nil }
        return min(max(0, date.timeIntervalSinceNow), 86_400)
    }
}
