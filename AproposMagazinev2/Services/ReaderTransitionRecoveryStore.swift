import CryptoKit
import Foundation

/// Installation-wide recovery evidence. Construction performs no I/O.
/// The first marker is immutable; neither account changes nor a missing read
/// grant authority to reopen writers. There is deliberately no removal API.
/// A shared queue serializes these instances within this process. Atomic rename
/// and readback do not prove fsync/power-loss durability or cross-process locking.
@MainActor
final class ReaderTransitionRecoveryStore {
    struct Marker: Equatable, Sendable {
        let binding: ReaderMembershipContract.Binding
        let transitionID: UUID

        init(binding: ReaderMembershipContract.Binding, transitionID: UUID) {
            self.binding = binding
            self.transitionID = transitionID
        }
    }
    enum DeletionPhase: String, Codable, Sendable { case parent, ledger }
    struct DeletionCheckpoint: Equatable, Sendable {
        let marker: Marker
        let request: ReaderAccountDeletionContract.Request
        let phase: DeletionPhase
        let configurationDigest: String

        init(marker: Marker, request: ReaderAccountDeletionContract.Request, phase: DeletionPhase,
             configurationDigest: String) throws {
            guard marker.binding.ownerUID == request.expectedUID, marker.binding.epoch == request.membershipEpoch,
                  Self.validDigest(configurationDigest) else { throw Failure.invalidCheckpoint }
            self.marker = marker; self.request = request; self.phase = phase
            self.configurationDigest = configurationDigest
        }
        nonisolated private static func validDigest(_ value: String) -> Bool {
            value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
        nonisolated func isSameFamily(as other: Self) -> Bool {
            marker == other.marker && request == other.request && configurationDigest == other.configurationDigest
        }
    }
    /// Original pending commit, never credentials or permission to send. The
    /// whole decoded installation record (including its ACK) is fingerprinted;
    /// callers must obtain the unchanged key from readExisting on every attempt.
    struct PushCommitCheckpoint: Equatable, Sendable {
        let checkpoint: DeletionCheckpoint
        let snapshot: ReaderAccountDeletionContract.PushSnapshot
        let recordDigest: String

        init(checkpoint: DeletionCheckpoint, snapshot: ReaderAccountDeletionContract.PushSnapshot, recordDigest: String) throws {
            guard checkpoint.phase == .ledger, snapshot.schemaVersion == 1,
                  snapshot.ownerUID == checkpoint.request.expectedUID,
                  PushRegistrationValidation.validHash(recordDigest) else { throw Failure.invalidPushCheckpoint }
            // Validate the full typed tuple, including its independently scoped
            // installation epoch, rather than checking only the state digest.
            do {
                _ = try ReaderAccountDeletionContract.PushSnapshot(requestId: snapshot.requestId, installationId: snapshot.installationId,
                    appId: snapshot.appId, ownerUID: snapshot.ownerUID, ownerEpoch: snapshot.ownerEpoch,
                    revision: snapshot.revision, clientRevision: snapshot.clientRevision, stateDigest: snapshot.stateDigest)
            } catch { throw Failure.invalidPushCheckpoint }
            self.checkpoint = checkpoint; self.snapshot = snapshot; self.recordDigest = recordDigest
        }

        nonisolated static func recordDigest(for record: PushInstallationRecord) throws -> String {
            try record.validate()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .millisecondsSince1970
            let canonical = try encoder.encode(record)
            guard canonical.count <= 4_096 else { throw Failure.limitExceeded }
            // Version/domain separation is part of the persistent fingerprint.
            // The temporary bytes are not retained in the checkpoint sidecar.
            let input = Data("apropos-push-installation-record-v1\n".utf8) + canonical
            return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
        }

        nonisolated func commitRequest(key: String) throws -> ReaderAccountDeletionContract.PushRequest {
            let original = checkpoint.request
            let ledger = try ReaderAccountDeletionContract.LedgerRequest(expectedUID: original.expectedUID,
                membershipEpoch: original.membershipEpoch, parentRequestID: original.requestID)
            return try .init(expectedUID: original.expectedUID, membershipEpoch: original.membershipEpoch,
                parentRequestID: original.requestID, ledgerRequestID: ledger.requestID,
                installation: .init(installationId: snapshot.installationId, key: key, requestId: snapshot.requestId,
                    expected: .init(ownerEpoch: snapshot.ownerEpoch, revision: snapshot.revision, clientRevision: snapshot.clientRevision),
                    snapshot: snapshot), scope: ReaderAccountDeletionContract.pushScope)
        }
    }
    struct Resumption: Equatable, Sendable {
        let marker: Marker?
        let checkpoint: DeletionCheckpoint?
        let pushCommit: PushCommitCheckpoint?
        init(marker: Marker?, checkpoint: DeletionCheckpoint?, pushCommit: PushCommitCheckpoint? = nil) {
            self.marker = marker; self.checkpoint = checkpoint; self.pushCommit = pushCommit
        }
    }
    enum Failure: Error, Equatable, Sendable {
        case readFailed, invalidMarker, conflictingMarker, writeFailed
        case unconfirmedSeal, limitExceeded
        case invalidCheckpoint, conflictingCheckpoint, missingCheckpoint, unconfirmedCheckpoint
        case invalidPushCheckpoint, conflictingPushCheckpoint, missingPushCheckpoint, unconfirmedPushCheckpoint, unconfirmedPushCommit
    }
    typealias Replace = @Sendable (Data, URL) throws -> Void
    nonisolated static let maximumMarkerBytes = 4_096
    nonisolated static let maximumCheckpointBytes = 4_096
    nonisolated static let maximumPushCommitBytes = 16_384
    nonisolated static let pushCommitScope = "reader-push-commit-continuation-v1"
    nonisolated static let deletionScope = "reader-deletion-continuation-v1"
    static let maximumPendingJobs = 64

    /// Call with the already validated HTTP configuration. No token is stored.
    nonisolated static func deletionConfigurationDigest(projectID: String, appID: String, endpoint: URL) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
        // Encoding a fixed array of strings cannot fail.
        let bytes = try! encoder.encode([projectID, appID, endpoint.absoluteString])
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private enum Work: Sendable {
        case read, seal(Marker), resumption
        case checkpoint(DeletionCheckpoint, expected: DeletionCheckpoint?)
        case pushCommit(PushCommitCheckpoint, expected: PushCommitCheckpoint?)
    }
    private enum WorkResult: Sendable {
        case marker(Marker?), resumption(Resumption), checkpoint(DeletionCheckpoint), pushCommit(PushCommitCheckpoint)
    }
    private enum Completion {
        case read(@MainActor (Result<Marker?, Error>) -> Void)
        case seal(@MainActor (Result<Marker, Error>) -> Void)
        case resumption(@MainActor (Result<Resumption, Error>) -> Void)
        case checkpoint(@MainActor (Result<DeletionCheckpoint, Error>) -> Void)
        case pushCommit(@MainActor (Result<PushCommitCheckpoint, Error>) -> Void)

        @MainActor func call(_ result: Result<WorkResult, Error>) {
            switch self {
            case .read(let callback): callback(result.flatMap {
                guard case .marker(let value) = $0 else { return .failure(Failure.readFailed) }
                return .success(value)
            })
            case .seal(let callback): callback(result.flatMap {
                guard case .marker(let value?) = $0 else { return .failure(Failure.unconfirmedSeal) }
                return .success(value)
            })
            case .resumption(let callback): callback(result.flatMap {
                guard case .resumption(let value) = $0 else { return .failure(Failure.readFailed) }
                return .success(value)
            })
            case .checkpoint(let callback): callback(result.flatMap {
                guard case .checkpoint(let value) = $0 else { return .failure(Failure.unconfirmedCheckpoint) }
                return .success(value)
            })
            case .pushCommit(let callback): callback(result.flatMap {
                guard case .pushCommit(let value) = $0 else { return .failure(Failure.unconfirmedPushCheckpoint) }
                return .success(value)
            })
            }
        }
    }
    private struct Job {
        let id = UUID()
        let work: Work
        let completion: Completion
    }
    nonisolated private static let ioQueue = DispatchQueue(label: "com.apropos.reader-transition-recovery", qos: .utility)
    private let rootDirectory: URL?
    private let replace: Replace
    private let beforeRead: @Sendable () throws -> Void
    private var pending: [Job] = []
    private var active: Job?

    init(rootDirectory: URL?, replace: @escaping Replace = { data, url in try data.write(to: url, options: .atomic) },
         beforeRead: @escaping @Sendable () throws -> Void = {}) {
        self.rootDirectory = rootDirectory; self.replace = replace; self.beforeRead = beforeRead
    }

    func read(completion: @escaping @MainActor (Result<Marker?, Error>) -> Void) {
        enqueue(.read, completion: .read(completion))
    }
    func seal(_ marker: Marker, completion: @escaping @MainActor (Result<Marker, Error>) -> Void) {
        enqueue(.seal(marker), completion: .seal(completion))
    }
    func readResumption(completion: @escaping @MainActor (Result<Resumption, Error>) -> Void) {
        enqueue(.resumption, completion: .resumption(completion))
    }
    func saveDeletionCheckpoint(_ checkpoint: DeletionCheckpoint, expected: DeletionCheckpoint?,
        completion: @escaping @MainActor (Result<DeletionCheckpoint, Error>) -> Void) {
        enqueue(.checkpoint(checkpoint, expected: expected), completion: .checkpoint(completion))
    }

    func savePushCommitCheckpoint(_ checkpoint: PushCommitCheckpoint, expected: PushCommitCheckpoint?,
        completion: @escaping @MainActor (Result<PushCommitCheckpoint, Error>) -> Void) {
        enqueue(.pushCommit(checkpoint, expected: expected), completion: .pushCommit(completion))
    }

    private func enqueue(_ work: Work, completion: Completion) {
        guard pending.count < Self.maximumPendingJobs else { completion.call(.failure(Failure.limitExceeded)); return }
        pending.append(Job(work: work, completion: completion)); pump()
    }
    private func pump() {
        guard active == nil, !pending.isEmpty else { return }
        let job = pending.removeFirst(); active = job
        let root = rootDirectory, replace = replace, beforeRead = beforeRead, work = job.work, id = job.id
        Self.ioQueue.async { [self] in
            let result = Result { try Self.perform(work, root: root, replace: replace, beforeRead: beforeRead) }
            Task { @MainActor [self] in self.finish(id: id, result: result) }
        }
    }
    private func finish(id: UUID, result: Result<WorkResult, Error>) {
        guard let job = active, job.id == id else { return }
        active = nil; job.completion.call(result); pump()
    }

    nonisolated private static func perform(_ work: Work, root: URL?, replace: Replace,
                                            beforeRead: @Sendable () throws -> Void) throws -> WorkResult {
        guard let root else { throw Failure.readFailed }
        switch work { case .read, .resumption: try beforeRead(); default: break }
        let existing = try readPair(root)
        switch work {
        case .read: return .marker(existing.marker)
        case .resumption: return .resumption(existing)
        case .seal(let marker):
            if let old = existing.marker {
                guard old == marker else { throw Failure.conflictingMarker }
                return .marker(old) // Never rewrite even differently formatted v1 bytes.
            }
            let bytes = try encode(marker), url = try location(root)
            try createDirectory(root)
            var writeFailure: Error?
            do { try replace(bytes, url) } catch { writeFailure = error }
            let verified: Resumption
            do { verified = try readPair(root) }
            catch { throw writeFailure ?? error }
            if let readback = verified.marker {
                guard readback == marker else { throw Failure.conflictingMarker }
                return .marker(readback)
            }
            throw writeFailure ?? Failure.unconfirmedSeal
        case .checkpoint(let candidate, let expected):
            guard existing.marker == candidate.marker else { throw Failure.conflictingMarker }
            if let old = existing.checkpoint {
                if old == candidate { return .checkpoint(old) }
                guard old == expected, old.isSameFamily(as: candidate), old.phase == .parent,
                      candidate.phase == .ledger else { throw Failure.conflictingCheckpoint }
            } else {
                guard expected == nil, candidate.phase == .parent else { throw Failure.conflictingCheckpoint }
            }
            let bytes = try encodeCheckpoint(candidate), url = try checkpointLocation(root)
            var writeFailure: Error?
            do { try replace(bytes, url) } catch { writeFailure = error }
            let verified: Resumption
            do { verified = try readPair(root) }
            catch { throw writeFailure ?? error }
            guard verified.marker == candidate.marker else { throw Failure.conflictingMarker }
            guard let readback = verified.checkpoint else { throw writeFailure ?? Failure.unconfirmedCheckpoint }
            guard readback == candidate else { throw Failure.conflictingCheckpoint }
            return .checkpoint(readback)
        case .pushCommit(let candidate, let expected):
            guard existing.marker == candidate.checkpoint.marker else { throw Failure.conflictingMarker }
            guard existing.checkpoint == candidate.checkpoint, candidate.checkpoint.phase == .ledger else {
                throw Failure.conflictingCheckpoint
            }
            if let old = existing.pushCommit {
                guard old == candidate, expected == nil || expected == old else { throw Failure.conflictingPushCheckpoint }
                return .pushCommit(old) // Never rewrite or renew an original snapshot.
            }
            guard expected == nil else { throw Failure.missingPushCheckpoint }
            let bytes = try encodePushCommit(candidate), url = try pushCommitLocation(root)
            // A thrown replacement is an uncertain outcome; only exact physical
            // readback can turn it into success.
            do { try replace(bytes, url) } catch { /* verified below */ }
            let verified: Resumption
            do { try beforeRead(); verified = try readPair(root) }
            catch {
                // Child-only uncertainty may retain same-candidate repair, but
                // never conceal a changed/corrupt/unreadable original family.
                try verifyPushFamily(root, candidate: candidate)
                throw Failure.unconfirmedPushCommit
            }
            guard verified.marker == candidate.checkpoint.marker else { throw Failure.conflictingMarker }
            guard verified.checkpoint == candidate.checkpoint else { throw Failure.conflictingCheckpoint }
            guard let readback = verified.pushCommit else { throw Failure.unconfirmedPushCommit }
            guard readback == candidate else { throw Failure.conflictingPushCheckpoint }
            return .pushCommit(readback)
        }
    }

    nonisolated private static func readPair(_ root: URL) throws -> Resumption {
        let marker = try readMarker(try location(root))
        let checkpoint = try readCheckpoint(try checkpointLocation(root))
        if let checkpoint {
            guard let marker, checkpoint.marker == marker else { throw Failure.conflictingMarker }
        }
        let pushCommit = try readPushCommit(try pushCommitLocation(root))
        if let pushCommit {
            guard let marker, marker == pushCommit.checkpoint.marker else { throw Failure.conflictingMarker }
            guard let checkpoint, checkpoint == pushCommit.checkpoint, checkpoint.phase == .ledger else {
                throw Failure.conflictingCheckpoint
            }
        }
        return Resumption(marker: marker, checkpoint: checkpoint, pushCommit: pushCommit)
    }

    nonisolated private static func verifyPushFamily(_ root: URL, candidate: PushCommitCheckpoint) throws {
        guard try readMarker(location(root)) == candidate.checkpoint.marker else { throw Failure.conflictingMarker }
        guard try readCheckpoint(checkpointLocation(root)) == candidate.checkpoint else { throw Failure.conflictingCheckpoint }
    }

    private struct PushCommitWire: Codable {
        let value: PushCommitCheckpoint
        init(_ value: PushCommitCheckpoint) { self.value = value }
        private enum Keys: String, CodingKey { case schemaVersion, scope, checkpoint, snapshot, recordDigest }
        init(from decoder: Decoder) throws {
            let all = try decoder.container(keyedBy: AnyKey.self)
            guard Set(all.allKeys.map(\.stringValue)) == ["schemaVersion", "scope", "checkpoint", "snapshot", "recordDigest"] else {
                throw Failure.invalidPushCheckpoint
            }
            let c = try decoder.container(keyedBy: Keys.self)
            guard try c.decode(Int.self, forKey: .schemaVersion) == 1,
                  try c.decode(String.self, forKey: .scope) == pushCommitScope else { throw Failure.invalidPushCheckpoint }
            value = try PushCommitCheckpoint(checkpoint: c.decode(CheckpointWire.self, forKey: .checkpoint).checkpoint,
                snapshot: c.decode(ReaderAccountDeletionContract.PushSnapshot.self, forKey: .snapshot),
                recordDigest: c.decode(String.self, forKey: .recordDigest))
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(1, forKey: .schemaVersion); try c.encode(pushCommitScope, forKey: .scope)
            try c.encode(CheckpointWire(value.checkpoint), forKey: .checkpoint)
            try c.encode(value.snapshot, forKey: .snapshot); try c.encode(value.recordDigest, forKey: .recordDigest)
        }
    }
    nonisolated private static func encodePushCommit(_ value: PushCommitCheckpoint) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(PushCommitWire(value))
        guard bytes.count <= maximumPushCommitBytes else { throw Failure.limitExceeded }; return bytes
    }
    nonisolated private static func readPushCommit(_ url: URL) throws -> PushCommitCheckpoint? {
        guard let bytes = try readBytes(url, maximum: maximumPushCommitBytes) else { return nil }
        do {
            let value = try JSONDecoder().decode(PushCommitWire.self, from: bytes).value
            // Exact canonical bytes reject unknown/duplicate keys, aliases and
            // any lossy decode. This is a new sidecar, not a legacy migration.
            guard try encodePushCommit(value) == bytes else { throw Failure.invalidPushCheckpoint }
            return value
        } catch { throw Failure.invalidPushCheckpoint }
    }
    nonisolated private static func pushCommitLocation(_ root: URL) throws -> URL {
        _ = try location(root)
        return root.appendingPathComponent("reader-push-commit-v1.json", isDirectory: false)
    }

    private struct CheckpointWire: Codable {
        let checkpoint: DeletionCheckpoint
        init(_ checkpoint: DeletionCheckpoint) { self.checkpoint = checkpoint }
        private enum Keys: String, CodingKey { case schemaVersion, scope, marker, request, requestID, phase, configurationDigest }
        init(from decoder: Decoder) throws {
            let all = try decoder.container(keyedBy: AnyKey.self)
            guard Set(all.allKeys.map(\.stringValue)) == ["schemaVersion", "scope", "marker", "request", "requestID", "phase", "configurationDigest"] else {
                throw Failure.invalidCheckpoint
            }
            let values = try decoder.container(keyedBy: Keys.self)
            guard try values.decode(Int.self, forKey: .schemaVersion) == 1,
                  try values.decode(String.self, forKey: .scope) == deletionScope else { throw Failure.invalidCheckpoint }
            let markerWire = try values.decode(Wire.self, forKey: .marker)
            let requestDecoder = try values.superDecoder(forKey: .request)
            let requestKeys = try requestDecoder.container(keyedBy: AnyKey.self)
            guard Set(requestKeys.allKeys.map(\.stringValue)) == ["expectedUID", "membershipEpoch"] else { throw Failure.invalidCheckpoint }
            let request = try ReaderAccountDeletionContract.Request(from: requestDecoder)
            guard try values.decode(String.self, forKey: .requestID) == request.requestID else { throw Failure.invalidCheckpoint }
            checkpoint = try DeletionCheckpoint(marker: Marker(binding: markerWire.binding, transitionID: markerWire.transitionID),
                request: request, phase: values.decode(DeletionPhase.self, forKey: .phase),
                configurationDigest: values.decode(String.self, forKey: .configurationDigest))
        }
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: Keys.self)
            try values.encode(1, forKey: .schemaVersion); try values.encode(deletionScope, forKey: .scope)
            try values.encode(Wire(checkpoint.marker), forKey: .marker); try values.encode(checkpoint.request, forKey: .request)
            try values.encode(checkpoint.request.requestID, forKey: .requestID); try values.encode(checkpoint.phase, forKey: .phase)
            try values.encode(checkpoint.configurationDigest, forKey: .configurationDigest)
        }
    }
    nonisolated private static func encodeCheckpoint(_ checkpoint: DeletionCheckpoint) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(CheckpointWire(checkpoint))
        guard bytes.count <= maximumCheckpointBytes else { throw Failure.limitExceeded }; return bytes
    }
    nonisolated private static func readCheckpoint(_ url: URL) throws -> DeletionCheckpoint? {
        guard let bytes = try readBytes(url, maximum: maximumCheckpointBytes) else { return nil }
        do { return try JSONDecoder().decode(CheckpointWire.self, from: bytes).checkpoint }
        catch { throw Failure.invalidCheckpoint }
    }
    nonisolated private static func checkpointLocation(_ root: URL) throws -> URL {
        _ = try location(root)
        return root.appendingPathComponent("reader-deletion-v1.json", isDirectory: false)
    }

    private struct Wire: Codable {
        let binding: ReaderMembershipContract.Binding
        let transitionID: UUID
        init(_ marker: Marker) { binding = marker.binding; transitionID = marker.transitionID }
        private enum CodingKeys: String, CodingKey { case schemaVersion, binding, transitionID }
        init(from decoder: Decoder) throws {
            let all = try decoder.container(keyedBy: AnyKey.self)
            guard Set(all.allKeys.map(\.stringValue)) == ["schemaVersion", "binding", "transitionID"] else {
                throw Failure.invalidMarker
            }
            let values = try decoder.container(keyedBy: CodingKeys.self)
            guard try values.decode(Int.self, forKey: .schemaVersion) == 1 else { throw Failure.invalidMarker }
            binding = try values.decode(ReaderMembershipContract.Binding.self, forKey: .binding)
            let text = try values.decode(String.self, forKey: .transitionID)
            guard let uuid = UUID(uuidString: text), uuid.uuidString.lowercased() == text else { throw Failure.invalidMarker }
            transitionID = uuid
        }
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(1, forKey: .schemaVersion)
            try values.encode(binding, forKey: .binding)
            try values.encode(transitionID.uuidString.lowercased(), forKey: .transitionID)
        }
    }
    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    nonisolated private static func encode(_ marker: Marker) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Wire(marker))
        guard data.count <= maximumMarkerBytes else { throw Failure.limitExceeded }
        return data
    }

    nonisolated private static func location(_ root: URL) throws -> URL {
        guard root.isFileURL, root.path.hasPrefix("/") else { throw Failure.readFailed }
        if let type = try fileType(root), type != .typeDirectory { throw Failure.readFailed }
        return root.appendingPathComponent("reader-transition-v1.json", isDirectory: false)
    }
    nonisolated private static func createDirectory(_ root: URL) throws {
        if let type = try fileType(root) {
            guard type == .typeDirectory else { throw Failure.writeFailed }
        } else {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            guard try fileType(root) == .typeDirectory else { throw Failure.writeFailed }
        }
    }
    nonisolated private static func fileType(_ url: URL) throws -> FileAttributeType? {
        do { return try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType }
        catch let error as NSError where error.domain == NSCocoaErrorDomain
            && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) { return nil }
    }
    nonisolated private static func readBytes(_ url: URL, maximum: Int) throws -> Data? {
        guard let type = try fileType(url) else { return nil }
        guard type == .typeRegular else { throw Failure.readFailed }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let bytes = try handle.read(upToCount: maximum + 1) ?? Data()
        guard bytes.count <= maximum, (try handle.read(upToCount: 1) ?? Data()).isEmpty else { throw Failure.limitExceeded }
        return bytes
    }
    nonisolated private static func readMarker(_ url: URL) throws -> Marker? {
        guard let bytes = try readBytes(url, maximum: maximumMarkerBytes) else { return nil }
        do {
            let wire = try JSONDecoder().decode(Wire.self, from: bytes)
            return Marker(binding: wire.binding, transitionID: wire.transitionID)
        } catch { throw Failure.invalidMarker }
    }
}
