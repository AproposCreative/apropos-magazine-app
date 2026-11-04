import CryptoKit
import Foundation

enum PushRegistrationValidation {
    static let maximumRevision: Int64 = 9_007_199_254_740_991
    static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) == value.startIndex..<value.endIndex
    }
    static func hash(_ value: Data) -> String { SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined() }
    static func validID(_ value: String) -> Bool {
        matches(value, "^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$")
    }
    static func validPrivateValue(_ value: String) -> Bool { matches(value, "^[a-zA-Z0-9_-]{40,128}$") }
    static func validHash(_ value: String) -> Bool { matches(value, "^[a-f0-9]{64}$") }
}

enum PushAccountContext: Equatable, Sendable {
    case unresolved
    case guest(epoch: UUID)
    case authenticated(uid: String, epoch: UUID)

    var ownerUID: String? {
        if case .authenticated(let uid, _) = self { return uid }
        return nil
    }
    var isResolved: Bool { self != .unresolved }
    var isValid: Bool {
        guard isResolved else { return false }
        return ownerUID.map { PushRegistrationValidation.matches($0, "^[a-zA-Z0-9_-]{1,128}$") } ?? true
    }
}

struct PushRecipientPreferences: Codable, Equatable, Sendable {
    enum Articles: String, Codable, Sendable { case all, categories, off }
    var articles: Articles
    var categoryIds: [String]
    var podcasts: Bool

    func normalized() throws -> Self {
        guard categoryIds.count <= 100, categoryIds.allSatisfy({ PushRegistrationValidation.matches($0, "^[a-zA-Z0-9_-]{1,100}$") }) else {
            throw PushRegistrationFailure.invalidResponse
        }
        let ids = Array(Set(categoryIds)).sorted()
        guard articles == .categories ? !ids.isEmpty : ids.isEmpty else { throw PushRegistrationFailure.invalidResponse }
        return .init(articles: articles, categoryIds: ids, podcasts: podcasts)
    }
}

struct PushRegistrationIntent: Equatable, Sendable {
    let context: PushAccountContext
    let permission: Bool
    let preferences: PushRecipientPreferences
    let token: String?

    var enabled: Bool { permission && (preferences.articles != .off || preferences.podcasts) }
    func normalized() throws -> Self {
        guard context.isValid else { throw PushRegistrationFailure.authentication }
        let prefs = try preferences.normalized()
        let active = permission && (prefs.articles != .off || prefs.podcasts)
        if active {
            guard let token, token.count >= 20, token.count <= 4096,
                  token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { throw PushRegistrationFailure.invalidResponse }
        }
        return .init(context: context, permission: permission, preferences: prefs, token: active ? token : nil)
    }
    func fingerprint() throws -> String {
        struct Signature: Encodable {
            let ownerUID: String?
            let permission: Bool
            let preferences: PushRecipientPreferences
            let tokenHash: String?
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try PushRegistrationValidation.hash(encoder.encode(Signature(ownerUID: context.ownerUID, permission: permission,
            preferences: preferences, tokenHash: token.map { PushRegistrationValidation.hash(Data($0.utf8)) })))
    }
}

struct PushRegistrationRequest: Encodable, Equatable, Sendable {
    let installationId: String
    let key: String
    let clientRevision: Int64
    let permission: Bool
    let preferences: PushRecipientPreferences
    let token: String?
}
struct PushConfirmationRequest: Encodable, Equatable, Sendable {
    let installationId: String
    let key: String
    let challengeId: String
    let nonce: String
}
enum PushRegistrationCall: Equatable, Sendable {
    case register(PushRegistrationRequest)
    case confirm(PushConfirmationRequest)
    var path: String { if case .register = self { return "register" }; return "confirm" }
    func body() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        switch self {
        case .register(let value): return try encoder.encode(value)
        case .confirm(let value): return try encoder.encode(value)
        }
    }
}
struct PushRegistrationTicket: Equatable, Sendable {
    let generation: UUID
    let context: PushAccountContext
    let installationId: String
    let clientRevision: Int64
}
struct PushRegistrationReceipt: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable { case pending, active, disabled }
    let status: Status
    let installationId: String
    let clientRevision: Int64
    let revision: Int64?
    let challengeId: String?
    let binding: PushAcknowledgedInstallationBinding?

    init(status: Status, installationId: String, clientRevision: Int64, revision: Int64?,
         challengeId: String?, binding: PushAcknowledgedInstallationBinding? = nil) {
        self.status = status; self.installationId = installationId; self.clientRevision = clientRevision
        self.revision = revision; self.challengeId = challengeId; self.binding = binding
    }
}

/// Historical server acknowledgement, never current deletion/startup authority.
/// Installation ownerEpoch is independent of the reader membership epoch.
struct PushAcknowledgedInstallationBinding: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let installationId: String
    let appId: String
    let ownerUID: String?
    let ownerEpoch: Int64
    let revision: Int64
    let clientRevision: Int64
    let status: PushRegistrationReceipt.Status

    func validate() throws {
        guard schemaVersion == 1, PushRegistrationValidation.validID(installationId),
              !appId.isEmpty, appId.utf8.count <= 256, appId.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              ownerUID.map({ PushRegistrationValidation.matches($0, "^[a-zA-Z0-9_-]{1,128}$") }) ?? true,
              [ownerEpoch, revision, clientRevision].allSatisfy({ $0 > 0 && $0 <= PushRegistrationValidation.maximumRevision }) else {
            throw PushRegistrationFailure.invalidResponse
        }
    }

    func matches(_ receipt: PushRegistrationReceipt, ticket: PushRegistrationTicket, expectedAppID: String) -> Bool {
        guard (try? validate()) != nil, appId == expectedAppID, ownerUID == ticket.context.ownerUID,
              installationId == ticket.installationId, clientRevision == ticket.clientRevision,
              status == receipt.status else { return false }
        // The legacy pending receipt deliberately has no top-level server revision.
        return receipt.revision.map { $0 == revision } ?? (status == .pending)
    }
}

/// Monotone cancellation checked on the vault's physical storage thread, without
/// awaiting MainActor while holding a storage lock. Revocation cannot undo a write.
final class PushRegistrationBindingLease: @unchecked Sendable {
    private let lock = NSLock()
    private var open = true
    private let parent: PushRegistrationBindingLease?
    init(parent: PushRegistrationBindingLease? = nil) { self.parent = parent }
    var isValid: Bool {
        lock.lock(); let local = open; lock.unlock()
        return local && (parent?.isValid ?? true)
    }
    func revoke() { lock.lock(); open = false; lock.unlock() }
}
enum PushRegistrationFailure: Error, Equatable {
    case transient(retryAfter: TimeInterval?)
    case authentication, forbidden, conflict, invalidResponse, cancelled
}
enum PushRegistrationBlock: Equatable {
    case storage, invalidIntent, authentication, forbidden, conflict, invalidResponse, retryLimit, challengeMismatch, clock
}
enum PushRegistrationState: Equatable {
    case idle, waitingForAccount, waitingForToken, preparing, registering, pending, confirming, active, disabled, proofExpired
    case retryWaiting(until: Date)
    case blocked(PushRegistrationBlock)
}
