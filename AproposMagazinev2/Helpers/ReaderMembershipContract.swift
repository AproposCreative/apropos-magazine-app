import Foundation

/// Strict projection of the staged worker's private membership row. Decoding
/// proves only shape and binding; it performs no I/O and grants no authority.
enum ReaderMembershipContract {
    enum Failure: Error, Equatable { case invalidMembership }

    struct Binding: Codable, Equatable, Sendable {
        let ownerUID: String
        let epoch: Int64

        init(ownerUID: String, epoch: Int64) throws {
            do { _ = try ReaderAccountDeletionContract.Request(expectedUID: ownerUID, membershipEpoch: epoch) }
            catch { throw Failure.invalidMembership }
            self.ownerUID = ownerUID
            self.epoch = epoch
        }

        private enum CodingKeys: String, CodingKey { case ownerUID, epoch }

        init(from decoder: Decoder) throws {
            do {
                let keys = try decoder.container(keyedBy: AnyKey.self)
                guard Set(keys.allKeys.map(\.stringValue)) == ["ownerUID", "epoch"] else { throw Failure.invalidMembership }
                let values = try decoder.container(keyedBy: CodingKeys.self)
                try self.init(ownerUID: values.decode(String.self, forKey: .ownerUID),
                              epoch: values.decode(Int64.self, forKey: .epoch))
            } catch { throw Failure.invalidMembership }
        }
    }

    enum State: String, Decodable, Sendable {
        case active
        case deletionFrozen = "deletion_frozen"
    }

    struct Record: Equatable, Sendable {
        let binding: Binding
        let state: State
        let deletionRequestID: String?

        fileprivate init(binding: Binding, state: State, deletionRequestID: String?) {
            self.binding = binding; self.state = state; self.deletionRequestID = deletionRequestID
        }
    }

    private struct WireRecord: Decodable {
        let schemaVersion: Int
        let ownerUID: String
        let epoch: Int64
        let state: State
        let deletionRequestID: String?
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    /// Missing/cache/untrusted rows must be classified by the future read
    /// boundary, never converted into an active membership by this decoder.
    static func decode(data: Data, expectedUID: String) throws -> Record {
        guard !data.isEmpty, data.count <= 16_384 else { throw Failure.invalidMembership }
        do {
            let row = try JSONDecoder().decode(WireRecord.self, from: data)
            let binding = try Binding(ownerUID: row.ownerUID, epoch: row.epoch)
            guard row.schemaVersion == 1, row.ownerUID == expectedUID,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw Failure.invalidMembership
            }
            let keys: Set<String> = ["schemaVersion", "ownerUID", "epoch", "state"]
            switch row.state {
            case .active:
                // A null request key is contradictory too; it is not absence.
                guard Set(object.keys) == keys else { throw Failure.invalidMembership }
            case .deletionFrozen:
                let request = try ReaderAccountDeletionContract.Request(expectedUID: binding.ownerUID, membershipEpoch: binding.epoch)
                guard Set(object.keys) == keys.union(["deletionRequestID"]),
                      row.deletionRequestID == request.requestID else { throw Failure.invalidMembership }
            }
            return Record(binding: binding, state: row.state, deletionRequestID: row.deletionRequestID)
        } catch { throw Failure.invalidMembership }
    }
}
