import CryptoKit
import Foundation

/// Inactive wire boundary for epoch-bound reader writes. It neither obtains a
/// membership nor upgrades an old favorites journal to a new account epoch.
enum ReaderMutationContract {
    static let scope = "reader-mutation-v1"
    static let maximumSafeInteger = ReaderAccountDeletionContract.maximumSafeInteger
    static let maximumRequestBytes = 65_536
    static let maximumReceiptBytes = 131_072

    enum Failure: Error, Equatable { case invalidRequest, invalidReceipt }
    enum Kind: String, Codable, Sendable {
        case favoriteSet = "favorite_set"
        case favoriteRemove = "favorite_remove"
        case preferencesSet = "preferences_set"
    }

    struct Preferences: Codable, Equatable, Sendable {
        let interestTopicIDs: [String]
        let onboardingCompleted: Bool

        init(interestTopicIDs: [String], onboardingCompleted: Bool) throws {
            // JS strings and Firestore document IDs are byte-sensitive. Do not
            // silently normalize, deduplicate, sort or truncate the intent.
            guard interestTopicIDs.count <= 20,
                  interestTopicIDs.allSatisfy(FavoritesRecordCodec.isValidID),
                  Set(interestTopicIDs.map { Data($0.utf8) }).count == interestTopicIDs.count else {
                throw Failure.invalidRequest
            }
            self.interestTopicIDs = interestTopicIDs
            self.onboardingCompleted = onboardingCompleted
        }

        private enum CodingKeys: String, CodingKey { case interestTopicIDs, onboardingCompleted }
        init(from decoder: Decoder) throws {
            do {
                try exactKeys(decoder, ["interestTopicIDs", "onboardingCompleted"])
                let values = try decoder.container(keyedBy: CodingKeys.self)
                try self.init(interestTopicIDs: values.decode([String].self, forKey: .interestTopicIDs),
                              onboardingCompleted: values.decode(Bool.self, forKey: .onboardingCompleted))
            } catch { throw Failure.invalidRequest }
        }
    }

    enum Payload: Equatable, Sendable {
        /// Display metadata only; never evidence of published article access.
        case favoriteSet(FavoritesRecord.Metadata)
        case favoriteRemove(articleID: String)
        case preferencesSet(Preferences)

        var kind: Kind {
            switch self {
            case .favoriteSet: return .favoriteSet
            case .favoriteRemove: return .favoriteRemove
            case .preferencesSet: return .preferencesSet
            }
        }
    }

    struct Request: Codable, Equatable, Sendable {
        let binding: ReaderMembershipContract.Binding
        let mutationID: String
        let expectedRevision: Int64
        let payload: Payload
        var expectedUID: String { binding.ownerUID }
        var membershipEpoch: Int64 { binding.epoch }
        var kind: Kind { payload.kind }

        /// Callers must supply the original persisted membership binding and
        /// mutation identity. There is deliberately no "current epoch" lookup.
        init(binding: ReaderMembershipContract.Binding, mutationID: String,
             expectedRevision: Int64, payload: Payload) throws {
            guard let uuid = UUID(uuidString: mutationID), uuid.uuidString.lowercased() == mutationID,
                  (0..<maximumSafeInteger).contains(expectedRevision) else { throw Failure.invalidRequest }
            switch payload {
            case .favoriteSet(let metadata):
                guard metadata.valid, validArticleID(metadata.id), validMetadataURLs(metadata) else { throw Failure.invalidRequest }
            case .favoriteRemove(let articleID):
                guard validArticleID(articleID) else { throw Failure.invalidRequest }
            case .preferencesSet: break // The immutable value has already been validated.
            }
            self.binding = binding
            self.mutationID = mutationID
            self.expectedRevision = expectedRevision
            self.payload = payload
            _ = try ReaderMutationContract.encode(self)
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion, expectedUID, membershipEpoch, mutationID, expectedRevision, kind, payload
        }

        init(from decoder: Decoder) throws {
            do {
                try exactKeys(decoder, ["schemaVersion", "expectedUID", "membershipEpoch", "mutationID", "expectedRevision", "kind", "payload"])
                let values = try decoder.container(keyedBy: CodingKeys.self)
                guard try values.decode(Int.self, forKey: .schemaVersion) == 1 else { throw Failure.invalidRequest }
                let binding = try ReaderMembershipContract.Binding(
                    ownerUID: values.decode(String.self, forKey: .expectedUID),
                    epoch: values.decode(Int64.self, forKey: .membershipEpoch))
                let kind = try values.decode(Kind.self, forKey: .kind)
                let payload = try decodePayload(kind: kind, from: values.superDecoder(forKey: .payload))
                try self.init(binding: binding, mutationID: values.decode(String.self, forKey: .mutationID),
                              expectedRevision: values.decode(Int64.self, forKey: .expectedRevision), payload: payload)
            } catch { throw Failure.invalidRequest }
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(1, forKey: .schemaVersion)
            try values.encode(expectedUID, forKey: .expectedUID)
            try values.encode(membershipEpoch, forKey: .membershipEpoch)
            try values.encode(mutationID, forKey: .mutationID)
            try values.encode(expectedRevision, forKey: .expectedRevision)
            try values.encode(kind, forKey: .kind)
            switch payload {
            case .favoriteSet(let metadata): try values.encode(metadata, forKey: .payload)
            case .favoriteRemove(let articleID): try values.encode(Removal(articleID: articleID), forKey: .payload)
            case .preferencesSet(let preferences): try values.encode(preferences, forKey: .payload)
            }
        }

        /// Matches JSON.stringify([scope, uid, epoch, mutationID]) in the worker.
        /// All four components are validated ASCII, with no JSON escaping needed.
        var requestID: String {
            let canonical = "[\"\(scope)\",\"\(expectedUID)\",\(membershipEpoch),\"\(mutationID)\"]"
            return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            // Swift String equality folds canonical Unicode variants; the wire
            // and server fingerprint do not. Preserve every original UTF-8 value.
            guard let left = try? ReaderMutationContract.encode(lhs),
                  let right = try? ReaderMutationContract.encode(rhs) else { return false }
            return left == right
        }
    }

    enum Status: String, Decodable, Sendable { case committed }
    struct Receipt: Equatable, Sendable {
        let requestID: String
        let status: Status
        let request: Request
        let committedRevision: Int64
        fileprivate init(requestID: String, status: Status, request: Request, committedRevision: Int64) {
            self.requestID = requestID; self.status = status
            self.request = request; self.committedRevision = committedRevision
        }
    }

    /// Encoding a new request does not establish membership or write authority.
    static func encode(_ request: Request) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(request)
        guard data.count <= maximumRequestBytes else { throw Failure.invalidRequest }
        return data
    }

    /// Restoring an intent requires its original binding. A newer server epoch
    /// cannot retag old bytes, and a different account cannot adopt them.
    static func decodeRequest(data: Data, binding: ReaderMembershipContract.Binding) throws -> Request {
        guard !data.isEmpty, data.count <= maximumRequestBytes else { throw Failure.invalidRequest }
        do {
            let request = try JSONDecoder().decode(Request.self, from: data)
            guard request.binding == binding else { throw Failure.invalidRequest }
            return request
        } catch { throw Failure.invalidRequest }
    }

    /// A receipt proves only that this exact intent was committed at its
    /// historical revision. A replay is not the current favorite/preferences
    /// value and cannot restore membership or authorize any subsequent write.
    static func decodeReceipt(data: Data, for request: Request) throws -> Receipt {
        guard !data.isEmpty, data.count <= maximumReceiptBytes else { throw Failure.invalidReceipt }
        do {
            let wire = try JSONDecoder().decode(WireReceipt.self, from: data)
            guard wire.schemaVersion == 1, wire.scope == scope,
                  wire.requestID == request.requestID, wire.request == request,
                  wire.committedRevision == request.expectedRevision + 1 else { throw Failure.invalidReceipt }
            return Receipt(requestID: wire.requestID, status: wire.status,
                           request: wire.request, committedRevision: wire.committedRevision)
        } catch { throw Failure.invalidReceipt }
    }

    private struct Removal: Codable {
        let articleID: String
        init(articleID: String) { self.articleID = articleID }
        private enum CodingKeys: String, CodingKey { case articleID }
        init(from decoder: Decoder) throws {
            try exactKeys(decoder, ["articleID"])
            let values = try decoder.container(keyedBy: CodingKeys.self)
            articleID = try values.decode(String.self, forKey: .articleID)
        }
    }

    private struct WireReceipt: Decodable {
        let schemaVersion: Int
        let scope: String
        let requestID: String
        let status: Status
        let request: Request
        let committedRevision: Int64
        private enum CodingKeys: String, CodingKey { case schemaVersion, scope, requestID, status, request, committedRevision }
        init(from decoder: Decoder) throws {
            try exactKeys(decoder, ["schemaVersion", "scope", "requestID", "status", "request", "committedRevision"])
            let values = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
            scope = try values.decode(String.self, forKey: .scope)
            requestID = try values.decode(String.self, forKey: .requestID)
            status = try values.decode(Status.self, forKey: .status)
            request = try values.decode(Request.self, forKey: .request)
            committedRevision = try values.decode(Int64.self, forKey: .committedRevision)
        }
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    private static func exactKeys(_ decoder: Decoder, _ expected: Set<String>) throws {
        let values = try decoder.container(keyedBy: AnyKey.self)
        guard Set(values.allKeys.map(\.stringValue)) == expected else { throw Failure.invalidRequest }
    }

    private static func decodePayload(kind: Kind, from decoder: Decoder) throws -> Payload {
        switch kind {
        case .favoriteSet:
            let values = try decoder.container(keyedBy: AnyKey.self)
            let keys = Set(values.allKeys.map(\.stringValue))
            guard keys.isSubset(of: FavoritesRecord.Metadata.keys), keys.isSuperset(of: ["id", "pressAccreditation"]) else {
                throw Failure.invalidRequest
            }
            // Synthesized Codable would absorb optional nulls. Reject them
            // before decoding the existing, strictly typed metadata value.
            for key in values.allKeys where try values.decodeNil(forKey: key) { throw Failure.invalidRequest }
            return .favoriteSet(try FavoritesRecord.Metadata(from: decoder))
        case .favoriteRemove: return .favoriteRemove(articleID: try Removal(from: decoder).articleID)
        case .preferencesSet: return .preferencesSet(try Preferences(from: decoder))
        }
    }

    private static func validArticleID(_ value: String) -> Bool {
        FavoritesRecordCodec.isValidID(value) && !value.contains("/") && value != "." && value != ".."
            && !(value.utf8.count >= 4 && value.hasPrefix("__") && value.hasSuffix("__"))
    }

    private static func validMetadataURLs(_ metadata: FavoritesRecord.Metadata) -> Bool {
        [metadata.mobileImageURL, metadata.thumbURL, metadata.coverURL].allSatisfy { raw in
            guard let raw else { return true }
            // WHATWG URL repairs abbreviated schemes and Foundation can expose
            // an empty host. The shared wire requires an explicit HTTP(S) host.
            guard raw.lowercased().hasPrefix("https://") || raw.lowercased().hasPrefix("http://"),
                  let host = URL(string: raw)?.host, !host.isEmpty else { return false }
            return true
        }
    }
}
