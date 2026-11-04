import Foundation

/// Inactive, SDK-free wire validation. A decoded snapshot is not installation-
/// wide writer authority, an SDK-start permit, or evidence of server migration.
/// The caller must still verify current context, trusted transport and expiry.
enum ReaderAuthoritativeReadContract {
    static let membershipScope = "reader-membership-read-v1"
    static let resourceScope = "reader-resource-read-v1"
    static let maximumRequestBytes = 4_096
    static let maximumResponseBytes = 131_072
    static let maximumSafeInteger = ReaderMutationContract.maximumSafeInteger
    enum Failure: Error, Equatable { case invalidRequest, invalidResponse }

    struct MembershipRequest: Codable, Equatable, Sendable {
        let expectedUID: String
        let readID: String
        init(expectedUID: String, readID: String) throws {
            do { _ = try ReaderMembershipContract.Binding(ownerUID: expectedUID, epoch: 1) }
            catch { throw Failure.invalidRequest }
            guard validReadID(readID) else { throw Failure.invalidRequest }
            self.expectedUID = expectedUID; self.readID = readID
            _ = try ReaderAuthoritativeReadContract.encode(self)
        }
        private enum CodingKeys: String, CodingKey { case schemaVersion, expectedUID, readID }
        init(from decoder: Decoder) throws {
            do {
                try exactKeys(decoder, ["schemaVersion", "expectedUID", "readID"])
                let values = try decoder.container(keyedBy: CodingKeys.self)
                guard try values.decode(Int.self, forKey: .schemaVersion) == 1 else { throw Failure.invalidRequest }
                try self.init(expectedUID: values.decode(String.self, forKey: .expectedUID), readID: values.decode(String.self, forKey: .readID))
            } catch { throw Failure.invalidRequest }
        }
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(1, forKey: .schemaVersion); try values.encode(expectedUID, forKey: .expectedUID)
            try values.encode(readID, forKey: .readID)
        }
    }

    enum Target: Codable, Equatable, Sendable {
        case favorite(id: String)
        case preferences
        var id: String { switch self { case .favorite(let id): return id; case .preferences: return "reader" } }
        var kind: String { switch self { case .favorite: return "favorite"; case .preferences: return "preferences" } }
        private enum CodingKeys: String, CodingKey { case kind, id }
        init(from decoder: Decoder) throws {
            try exactKeys(decoder, ["kind", "id"])
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try values.decode(String.self, forKey: .kind), id = try values.decode(String.self, forKey: .id)
            switch kind {
            case "favorite": self = .favorite(id: id)
            case "preferences" where id == "reader": self = .preferences
            default: throw Failure.invalidRequest
            }
        }
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(kind, forKey: .kind); try values.encode(id, forKey: .id)
        }
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.kind == rhs.kind && Data(lhs.id.utf8) == Data(rhs.id.utf8)
        }
    }

    struct ResourceRequest: Codable, Equatable, Sendable {
        let binding: ReaderMembershipContract.Binding
        let target: Target
        let readID: String
        var expectedUID: String { binding.ownerUID }
        var membershipEpoch: Int64 { binding.epoch }
        init(binding: ReaderMembershipContract.Binding, target: Target, readID: String) throws {
            guard validReadID(readID) else { throw Failure.invalidRequest }
            // Reuse the bounded direct-document-ID policy, without dispatching
            // or persisting a mutation or inferring a newer membership epoch.
            if case .favorite(let id) = target {
                do { _ = try ReaderMutationContract.Request(binding: binding, mutationID: readID,
                    expectedRevision: 0, payload: .favoriteRemove(articleID: id)) }
                catch { throw Failure.invalidRequest }
            }
            self.binding = binding; self.target = target; self.readID = readID
            _ = try ReaderAuthoritativeReadContract.encode(self)
        }
        private enum CodingKeys: String, CodingKey { case schemaVersion, expectedUID, readID, membershipEpoch, target }
        init(from decoder: Decoder) throws {
            do {
                try exactKeys(decoder, ["schemaVersion", "expectedUID", "readID", "membershipEpoch", "target"])
                let values = try decoder.container(keyedBy: CodingKeys.self)
                guard try values.decode(Int.self, forKey: .schemaVersion) == 1 else { throw Failure.invalidRequest }
                let binding = try ReaderMembershipContract.Binding(ownerUID: values.decode(String.self, forKey: .expectedUID),
                    epoch: values.decode(Int64.self, forKey: .membershipEpoch))
                try self.init(binding: binding, target: values.decode(Target.self, forKey: .target), readID: values.decode(String.self, forKey: .readID))
            } catch { throw Failure.invalidRequest }
        }
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(1, forKey: .schemaVersion); try values.encode(expectedUID, forKey: .expectedUID)
            try values.encode(membershipEpoch, forKey: .membershipEpoch); try values.encode(target, forKey: .target)
            try values.encode(readID, forKey: .readID)
        }
    }

    struct MembershipSnapshot: Equatable, Sendable {
        let request: MembershipRequest
        let membership: ReaderMembershipContract.Record?
        let validUntilMs: Int64
        fileprivate init(request: MembershipRequest, membership: ReaderMembershipContract.Record?, validUntilMs: Int64) {
            self.request = request; self.membership = membership; self.validUntilMs = validUntilMs
        }
    }
    struct Boundary: Decodable, Equatable, Sendable {
        let readerSchemaVersion: Int
        let writerFenceRevision: String
        let migrationRevision: String
        private enum CodingKeys: String, CodingKey { case readerSchemaVersion, writerFenceRevision, migrationRevision }
        init(from decoder: Decoder) throws {
            try exactKeys(decoder, ["readerSchemaVersion", "writerFenceRevision", "migrationRevision"])
            let values = try decoder.container(keyedBy: CodingKeys.self)
            readerSchemaVersion = try values.decode(Int.self, forKey: .readerSchemaVersion)
            writerFenceRevision = try values.decode(String.self, forKey: .writerFenceRevision)
            migrationRevision = try values.decode(String.self, forKey: .migrationRevision)
            guard readerSchemaVersion == 1, validHash(writerFenceRevision), validHash(migrationRevision) else { throw Failure.invalidResponse }
        }
    }
    enum ResourcePayload: Equatable, Sendable {
        case favorite(FavoritesRecord.Metadata)
        case preferences(ReaderMutationContract.Preferences)
        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.favorite(let left), .favorite(let right)):
                guard let a = try? canonical(left), let b = try? canonical(right) else { return false }; return a == b
            case (.preferences(let left), .preferences(let right)):
                guard let a = try? canonical(left), let b = try? canonical(right) else { return false }; return a == b
            default: return false
            }
        }
    }
    struct Resource: Equatable, Sendable {
        let revision: Int64
        let exists: Bool
        let payload: ResourcePayload?
        fileprivate init(revision: Int64, exists: Bool, payload: ResourcePayload?) {
            self.revision = revision; self.exists = exists; self.payload = payload
        }
    }
    struct ResourceSnapshot: Equatable, Sendable {
        let request: ResourceRequest
        let membership: ReaderMembershipContract.Record
        let boundary: Boundary
        let resource: Resource
        let validUntilMs: Int64
        fileprivate init(request: ResourceRequest, membership: ReaderMembershipContract.Record,
            boundary: Boundary, resource: Resource, validUntilMs: Int64) {
            self.request = request; self.membership = membership; self.boundary = boundary
            self.resource = resource; self.validUntilMs = validUntilMs
        }
    }

    static func encode(_ request: MembershipRequest) throws -> Data { try boundedRequest(request) }
    static func encode(_ request: ResourceRequest) throws -> Data { try boundedRequest(request) }
    static func decodeMembershipRequest(data: Data, expectedUID: String) throws -> MembershipRequest {
        guard !data.isEmpty, data.count <= maximumRequestBytes else { throw Failure.invalidRequest }
        do {
            let result = try JSONDecoder().decode(MembershipRequest.self, from: data)
            guard result.expectedUID == expectedUID else { throw Failure.invalidRequest }; return result
        } catch { throw Failure.invalidRequest }
    }
    static func decodeResourceRequest(data: Data, binding: ReaderMembershipContract.Binding) throws -> ResourceRequest {
        guard !data.isEmpty, data.count <= maximumRequestBytes else { throw Failure.invalidRequest }
        do {
            let result = try JSONDecoder().decode(ResourceRequest.self, from: data)
            guard result.binding == binding else { throw Failure.invalidRequest }; return result
        } catch { throw Failure.invalidRequest }
    }
    static func decodeMembershipResponse(data: Data, for request: MembershipRequest) throws -> MembershipSnapshot {
        do {
            let object = try responseObject(data, keys: ["schemaVersion", "scope", "request", "membership", "validUntilMs"])
            let wire = try JSONDecoder().decode(Envelope<MembershipRequest>.self, from: data)
            guard wire.schemaVersion == 1, wire.scope == membershipScope, wire.request == request,
                validExpiry(wire.validUntilMs) else { throw Failure.invalidResponse }
            let member = try membership(object["membership"]!, expectedUID: request.expectedUID)
            return MembershipSnapshot(request: wire.request, membership: member, validUntilMs: wire.validUntilMs)
        } catch { throw Failure.invalidResponse }
    }
    static func decodeResourceResponse(data: Data, for request: ResourceRequest) throws -> ResourceSnapshot {
        do {
            let object = try responseObject(data, keys: ["schemaVersion", "scope", "request", "membership", "validUntilMs", "boundary", "resource"])
            let wire = try JSONDecoder().decode(Envelope<ResourceRequest>.self, from: data)
            guard wire.schemaVersion == 1, wire.scope == resourceScope, wire.request == request, validExpiry(wire.validUntilMs),
                  let member = try membership(object["membership"]!, expectedUID: request.expectedUID),
                  member.binding == request.binding, member.state == .active else { throw Failure.invalidResponse }
            let boundary = try JSONDecoder().decode(Boundary.self, from: json(object["boundary"]!))
            guard let state = object["resource"] as? [String: Any], Set(state.keys) == ["revision", "exists", "payload"] else { throw Failure.invalidResponse }
            let fields = try JSONDecoder().decode(ResourceFields.self, from: json(state))
            guard (0...maximumSafeInteger).contains(fields.revision) else { throw Failure.invalidResponse }
            let payload: ResourcePayload?
            if fields.exists {
                guard fields.revision > 0 else { throw Failure.invalidResponse }
                payload = try resourcePayload(state["payload"]!, request: request)
            } else {
                guard state["payload"] is NSNull, request.target.kind == "favorite" || fields.revision == 0 else { throw Failure.invalidResponse }
                payload = nil
            }
            return ResourceSnapshot(request: wire.request, membership: member, boundary: boundary,
                resource: Resource(revision: fields.revision, exists: fields.exists, payload: payload), validUntilMs: wire.validUntilMs)
        } catch { throw Failure.invalidResponse }
    }

    private struct Envelope<Request: Decodable>: Decodable {
        let schemaVersion: Int
        let scope: String
        let request: Request
        let validUntilMs: Int64
    }
    private struct ResourceFields: Decodable { let revision: Int64; let exists: Bool }
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
    private static func validReadID(_ value: String) -> Bool {
        guard let uuid = UUID(uuidString: value) else { return false }; return uuid.uuidString.lowercased() == value
    }
    private static func validHash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func validExpiry(_ value: Int64) -> Bool { (1...maximumSafeInteger).contains(value) }
    private static func canonical<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    private static func boundedRequest<T: Encodable>(_ value: T) throws -> Data {
        let data = try canonical(value)
        guard data.count <= maximumRequestBytes else { throw Failure.invalidRequest }; return data
    }
    private static func json(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
    }
    private static func responseObject(_ data: Data, keys: Set<String>) throws -> [String: Any] {
        guard !data.isEmpty, data.count <= maximumResponseBytes,
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any], Set(result.keys) == keys else { throw Failure.invalidResponse }
        return result
    }
    private static func membership(_ raw: Any, expectedUID: String) throws -> ReaderMembershipContract.Record? {
        if raw is NSNull { return nil }
        let data = try json(raw)
        guard data.count <= maximumRequestBytes else { throw Failure.invalidResponse }
        return try ReaderMembershipContract.decode(data: data, expectedUID: expectedUID)
    }
    private static func resourcePayload(_ raw: Any, request: ResourceRequest) throws -> ResourcePayload {
        // Reuse the actual strict mutation payload decoder (keys, nulls, types,
        // URL/string/ID bounds). This temporary validation envelope is never
        // persisted or sent and is not a newly authorised mutation intent.
        let value: [String: Any] = ["schemaVersion": 1, "expectedUID": request.expectedUID,
            "membershipEpoch": request.membershipEpoch, "mutationID": request.readID, "expectedRevision": 0,
            "kind": request.target.kind == "favorite" ? "favorite_set" : "preferences_set", "payload": raw]
        let validated = try ReaderMutationContract.decodeRequest(data: json(value), binding: request.binding)
        switch validated.payload {
        case .favoriteSet(let metadata):
            guard Data(metadata.id.utf8) == Data(request.target.id.utf8) else { throw Failure.invalidResponse }
            return .favorite(metadata)
        case .preferencesSet(let preferences): return .preferences(preferences)
        case .favoriteRemove: throw Failure.invalidResponse
        }
    }
}
