import Foundation
import XCTest
@testable import Apropos

@MainActor
final class ReaderTransitionRecoveryStoreTests: XCTestCase {
    private typealias Store = ReaderTransitionRecoveryStore
    private typealias Marker = Store.Marker

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("reader-transition-recovery-" + UUID().uuidString, isDirectory: true)
    }
    private func marker(owner: String = "reader_a", epoch: Int64 = 7, id: UUID = UUID()) throws -> Marker {
        Marker(binding: try .init(ownerUID: owner, epoch: epoch), transitionID: id)
    }
    private func read(_ store: Store) async throws -> Marker? {
        try await withCheckedThrowingContinuation { continuation in
            store.read { continuation.resume(with: $0) }
        }
    }
    private func seal(_ store: Store, _ marker: Marker) async throws -> Marker {
        try await withCheckedThrowingContinuation { continuation in
            store.seal(marker) { continuation.resume(with: $0) }
        }
    }
    private func onlyFile(_ root: URL) throws -> URL {
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        return try XCTUnwrap(files.first)
    }
    private func failure<T>(_ operation: () async throws -> T) async -> Error? {
        do { _ = try await operation(); XCTFail("Expected failure"); return nil }
        catch { return error }
    }
    private func waitForStart(_ gate: Gate) async {
        let started = await Task.detached { gate.waitForStart() }.value
        XCTAssertTrue(started, "Physical marker replacement did not start")
    }

    func testConstructionAndMissingReadPerformNoDirectoryCreationOrReplacement() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let probe = Probe { _, _, _ in XCTFail("Unexpected replacement") }
        let store = Store(rootDirectory: root, replace: { try probe.replace($0, $1) })
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        let missing = try await read(store)
        XCTAssertNil(missing); XCTAssertEqual(probe.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testActualSealReadbackAndRestartPreserveOriginalBindingAndTransitionID() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try marker(epoch: ReaderAccountDeletionContract.maximumSafeInteger)
        let store = Store(rootDirectory: root)
        let result = try await seal(store, original)
        XCTAssertEqual(result, original)
        let path = try onlyFile(root)
        XCTAssertFalse(path.lastPathComponent.contains(original.binding.ownerUID))
        let data = try Data(contentsOf: path)
        XCTAssertLessThanOrEqual(data.count, Store.maximumMarkerBytes)
        let restarted = try await read(Store(rootDirectory: root))
        XCTAssertEqual(restarted, original)
        let retried = try await seal(Store(rootDirectory: root), original)
        XCTAssertEqual(retried, original); XCTAssertEqual(try Data(contentsOf: path), data)
    }

    func testDifferentOwnerEpochOrTransitionIDCannotReplaceFirstMarker() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try marker(), store = Store(rootDirectory: root)
        _ = try await seal(store, original)
        let path = try onlyFile(root), before = try Data(contentsOf: path)
        let candidates = [try marker(owner: "reader_b", id: original.transitionID),
            try marker(epoch: 8, id: original.transitionID), try marker()]
        for candidate in candidates {
            let error = await failure { try await seal(Store(rootDirectory: root), candidate) }
            XCTAssertEqual(error as? Store.Failure, .conflictingMarker)
            XCTAssertEqual(try Data(contentsOf: path), before)
        }
        let recovered = try await read(store); XCTAssertEqual(recovered, original)
    }

    func testExactRetryPreservesFirstFormattingAndNeverCallsReplace() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try marker()
        _ = try await seal(Store(rootDirectory: root), original)
        let path = try onlyFile(root), object = try JSONSerialization.jsonObject(with: Data(contentsOf: path))
        let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try pretty.write(to: path, options: .atomic)
        let probe = Probe { _, _, _ in throw Injected.failure }
        let result = try await seal(Store(rootDirectory: root, replace: { try probe.replace($0, $1) }), original)
        XCTAssertEqual(result, original); XCTAssertEqual(probe.count, 0)
        XCTAssertEqual(try Data(contentsOf: path), pretty)
    }

    func testCommitThenThrowIsConfirmedByDiskWithoutSecondPhysicalWrite() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try marker()
        let probe = Probe { _, data, url in
            try data.write(to: url, options: .atomic)
            throw Injected.failure
        }
        let store = Store(rootDirectory: root, replace: { try probe.replace($0, $1) })
        let result = try await seal(store, original)
        XCTAssertEqual(result, original); XCTAssertEqual(probe.count, 1)
        let retry = try await seal(store, original)
        XCTAssertEqual(retry, original); XCTAssertEqual(probe.count, 1)
        let restarted = try await read(Store(rootDirectory: root)); XCTAssertEqual(restarted, original)
    }

    func testFailureBeforeCommitRemainsFailureAndExplicitRetryCanSealOriginalMarker() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try marker()
        let probe = Probe { attempt, data, url in
            if attempt == 1 { throw Injected.failure }
            try data.write(to: url, options: .atomic)
        }
        let store = Store(rootDirectory: root, replace: { try probe.replace($0, $1) })
        let error = await failure { try await seal(store, original) }
        XCTAssertEqual(error as? Injected, .failure); XCTAssertEqual(probe.count, 1)
        let missing = try await read(store); XCTAssertNil(missing)
        let result = try await seal(store, original)
        XCTAssertEqual(result, original); XCTAssertEqual(probe.count, 2)
    }

    func testSuccessfulReplacementCallbackWithoutFileCannotConfirmSeal() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try marker(), probe = Probe { _, _, _ in }
        let store = Store(rootDirectory: root, replace: { try probe.replace($0, $1) })
        let error = await failure { try await seal(store, original) }
        XCTAssertEqual(error as? Store.Failure, .unconfirmedSeal); XCTAssertEqual(probe.count, 1)
        let missing = try await read(Store(rootDirectory: root)); XCTAssertNil(missing)
    }

    func testCorruptReadbackIsFailureAndNeverReplacedByRetry() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try marker(), corrupt = Data("interrupted-marker".utf8)
        let probe = Probe { _, data, url in
            try data.write(to: url, options: .atomic)
            try corrupt.write(to: url, options: .atomic)
        }
        let store = Store(rootDirectory: root, replace: { try probe.replace($0, $1) })
        let first = await failure { try await seal(store, original) }
        XCTAssertEqual(first as? Store.Failure, .invalidMarker)
        let second = await failure { try await seal(store, original) }
        XCTAssertEqual(second as? Store.Failure, .invalidMarker); XCTAssertEqual(probe.count, 1)
        XCTAssertEqual(try Data(contentsOf: onlyFile(root)), corrupt)
    }

    func testDifferentValidReadbackCannotAcknowledgeRequestedMarker() async throws {
        let root = directory(), otherRoot = directory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: otherRoot) }
        let original = try marker(), other = try marker(owner: "reader_b", epoch: 11)
        _ = try await seal(Store(rootDirectory: otherRoot), other)
        let otherBytes = try Data(contentsOf: onlyFile(otherRoot))
        let store = Store(rootDirectory: root, replace: { _, url in try otherBytes.write(to: url, options: .atomic) })
        let error = await failure { try await seal(store, original) }
        XCTAssertEqual(error as? Store.Failure, .conflictingMarker)
        let recovered = try await read(Store(rootDirectory: root)); XCTAssertEqual(recovered, other)
        XCTAssertEqual(try Data(contentsOf: onlyFile(root)), otherBytes)
    }

    func testMalformedSchemasTypesBindingsAndUnknownKeysArePreservedFailClosed() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let fixedID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"))
        let original = try marker(id: fixedID), store = Store(rootDirectory: root)
        _ = try await seal(store, original)
        let path = try onlyFile(root)
        let valid = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        var candidates: [[String: Any]] = []
        for (key, value) in [("schemaVersion", 2 as Any), ("schemaVersion", true as Any),
            ("schemaVersion", "1" as Any), ("transitionID", "invalid" as Any),
            ("transitionID", original.transitionID.uuidString as Any), ("unknown", true as Any)] {
            var object = valid; object[key] = value; candidates.append(object)
        }
        var missing = valid; missing.removeValue(forKey: "binding"); candidates.append(missing)
        let bindings: [[String: Any]] = [
            ["ownerUID": "reader_b/path", "epoch": 7], ["ownerUID": "", "epoch": 7],
            ["ownerUID": "reader_a", "epoch": 0], ["ownerUID": "reader_a", "epoch": -1],
            ["ownerUID": "reader_a", "epoch": 9_007_199_254_740_992 as Int64],
            ["ownerUID": "reader_a", "epoch": true], ["ownerUID": "reader_a", "epoch": "7"],
            ["ownerUID": "reader_a", "epoch": 7.5], ["ownerUID": "reader_a", "epoch": NSNull()],
            ["ownerUID": "reader_a", "epoch": 7, "unknown": "not accepted"]
        ]
        for binding in bindings { var object = valid; object["binding"] = binding; candidates.append(object) }
        let encoded = try candidates.map { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
        for bytes in [Data(), Data("broken json".utf8)] + encoded {
            try bytes.write(to: path, options: .atomic)
            let readError = await failure { try await read(store) }
            let sealError = await failure { try await seal(store, original) }
            XCTAssertEqual(readError as? Store.Failure, .invalidMarker)
            XCTAssertEqual(sealError as? Store.Failure, .invalidMarker)
            XCTAssertEqual(try Data(contentsOf: path), bytes)
        }
    }

    func testExactFileByteBoundAcceptedAndOversizeRefusedWithoutTruncation() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try marker(), store = Store(rootDirectory: root)
        _ = try await seal(store, original)
        let path = try onlyFile(root), canonical = try Data(contentsOf: path)
        var bounded = canonical; bounded.append(Data(repeating: 32, count: Store.maximumMarkerBytes - canonical.count))
        try bounded.write(to: path, options: .atomic)
        let accepted = try await read(store); XCTAssertEqual(accepted, original)
        _ = try await seal(store, original); XCTAssertEqual(try Data(contentsOf: path), bounded)
        let oversized = bounded + Data([32]); try oversized.write(to: path, options: .atomic)
        let readError = await failure { try await read(store) }
        let sealError = await failure { try await seal(store, original) }
        XCTAssertEqual(readError as? Store.Failure, .limitExceeded)
        XCTAssertEqual(sealError as? Store.Failure, .limitExceeded)
        XCTAssertEqual(try Data(contentsOf: path), oversized)
    }

    func testMarkerSymlinkIsNotFollowedOrReplaced() async throws {
        let root = directory(), outside = directory().appendingPathExtension("data")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let original = try marker(), store = Store(rootDirectory: root)
        _ = try await seal(store, original)
        let path = try onlyFile(root), bytes = try Data(contentsOf: path)
        try bytes.write(to: outside); try FileManager.default.removeItem(at: path)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: outside)
        let readError = await failure { try await read(store) }
        let sealError = await failure { try await seal(store, original) }
        XCTAssertEqual(readError as? Store.Failure, .readFailed)
        XCTAssertEqual(sealError as? Store.Failure, .readFailed)
        XCTAssertEqual(try Data(contentsOf: outside), bytes)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: path.path), outside.path)
    }

    func testSymlinkNonDirectoryAndNonFileRootsAreRefusedWithoutOutsideWrites() async throws {
        let root = directory(), outside = directory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: outside)
        let original = try marker(), linked = Store(rootDirectory: root)
        let linkedError = await failure { try await seal(linked, original) }
        XCTAssertEqual(linkedError as? Store.Failure, .readFailed)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
        try FileManager.default.removeItem(at: root); let bytes = Data("regular root".utf8); try bytes.write(to: root)
        let fileError = await failure { try await seal(Store(rootDirectory: root), original) }
        XCTAssertEqual(fileError as? Store.Failure, .readFailed); XCTAssertEqual(try Data(contentsOf: root), bytes)
        let networkURL = try XCTUnwrap(URL(string: "https://example.invalid/marker"))
        let networkError = await failure { try await read(Store(rootDirectory: networkURL)) }
        XCTAssertEqual(networkError as? Store.Failure, .readFailed)
    }

    func testConcurrentInstancesWithDifferentMarkersHaveExactlyOneWinner() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let gate = Gate(); defer { gate.release() }
        let first = try marker(), second = try marker(owner: "reader_b")
        let one = Store(rootDirectory: root, replace: { try gate.replace($0, $1) }), two = Store(rootDirectory: root)
        let accepted = expectation(description: "First marker committed"), rejected = expectation(description: "Other marker refused")
        one.seal(first) { result in
            if case .success(let marker) = result { XCTAssertEqual(marker, first) }
            else { XCTFail("First seal failed") }; accepted.fulfill()
        }
        await waitForStart(gate)
        two.seal(second) { result in
            if case .failure(let error) = result { XCTAssertEqual(error as? Store.Failure, .conflictingMarker) }
            else { XCTFail("Different marker overwrote original") }; rejected.fulfill()
        }
        gate.release(); await fulfillment(of: [accepted, rejected], timeout: 5)
        let actual = try await read(Store(rootDirectory: root)); XCTAssertEqual(actual, first)
        XCTAssertEqual(gate.count, 1); XCTAssertFalse(gate.wasMainThread)
    }

    func testConcurrentInstancesWithSameMarkerShareSinglePhysicalCommit() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let gate = Gate(); defer { gate.release() }
        let original = try marker(), probe = Probe { _, _, _ in throw Injected.failure }
        let one = Store(rootDirectory: root, replace: { try gate.replace($0, $1) })
        let two = Store(rootDirectory: root, replace: { try probe.replace($0, $1) })
        let done = expectation(description: "Both observe same durable marker"); done.expectedFulfillmentCount = 2
        one.seal(original) { result in
            if case .success(let marker) = result { XCTAssertEqual(marker, original) } else { XCTFail("First seal failed") }; done.fulfill()
        }
        await waitForStart(gate)
        two.seal(original) { result in
            if case .success(let marker) = result { XCTAssertEqual(marker, original) } else { XCTFail("Exact retry failed") }; done.fulfill()
        }
        gate.release(); await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(gate.count, 1); XCTAssertEqual(probe.count, 0)
    }

    func testQueueBoundRejectsExcessExactlyOnceWhileAcceptedJobsWaitForPhysicalReturn() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try marker(), gate = Gate(); defer { gate.release() }
        let store = Store(rootDirectory: root, replace: { try gate.replace($0, $1) })
        let committed = expectation(description: "Original physical commit")
        var physicalCompletion = false
        store.seal(original) { result in
            if case .failure = result { XCTFail("Held seal failed") }; physicalCompletion = true; committed.fulfill()
        }
        await waitForStart(gate)
        let reads = expectation(description: "All accepted reads finish"); reads.expectedFulfillmentCount = Store.maximumPendingJobs
        var completedReads = 0
        for _ in 0..<Store.maximumPendingJobs {
            store.read { result in
                if case .success(let marker) = result { XCTAssertEqual(marker, original) } else { XCTFail("Accepted read failed") }
                completedReads += 1; reads.fulfill()
            }
        }
        var refusedCalls = 0
        store.seal(original) { result in
            if case .failure(let error) = result { XCTAssertEqual(error as? Store.Failure, .limitExceeded) }
            else { XCTFail("Queue bound exceeded") }; refusedCalls += 1
        }
        XCTAssertEqual(refusedCalls, 1); XCTAssertEqual(completedReads, 0); XCTAssertFalse(physicalCompletion)
        gate.release(); await fulfillment(of: [committed, reads], timeout: 5)
        XCTAssertEqual(completedReads, Store.maximumPendingJobs); XCTAssertEqual(refusedCalls, 1)
        let retry = try await seal(store, original); XCTAssertEqual(retry, original)
    }

    func testCompletionReentryObservesDurableMarkerAndPreservesQueuedReadOrder() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try marker(), gate = Gate(); defer { gate.release() }
        let store = Store(rootDirectory: root, replace: { try gate.replace($0, $1) })
        let done = expectation(description: "Queued and reentrant reads finish"); done.expectedFulfillmentCount = 2
        var order: [String] = []
        store.seal(original) { result in
            if case .failure = result { XCTFail("Seal failed") }
            order.append("seal")
            store.read { result in
                if case .success(let marker) = result { XCTAssertEqual(marker, original) } else { XCTFail("Reentrant read failed") }
                order.append("reentrant"); done.fulfill()
            }
        }
        await waitForStart(gate)
        store.read { result in
            if case .success(let marker) = result { XCTAssertEqual(marker, original) } else { XCTFail("Queued read failed") }
            order.append("queued"); done.fulfill()
        }
        gate.release(); await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(order, ["seal", "queued", "reentrant"])
    }

    private enum Injected: Error, Equatable { case failure }
    private final class Probe: @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        private let action: @Sendable (Int, Data, URL) throws -> Void
        init(_ action: @escaping @Sendable (Int, Data, URL) throws -> Void) { self.action = action }
        var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
        func replace(_ data: Data, _ url: URL) throws {
            lock.lock(); calls += 1; let call = calls; lock.unlock()
            try action(call, data, url)
        }
    }
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        private var main = false
        private let started = DispatchSemaphore(value: 0)
        private let released = DispatchSemaphore(value: 0)
        var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
        var wasMainThread: Bool { lock.lock(); defer { lock.unlock() }; return main }
        func waitForStart() -> Bool { started.wait(timeout: .now() + 5) == .success }
        func release() { released.signal() }
        func replace(_ data: Data, _ url: URL) throws {
            lock.lock(); calls += 1; main = main || Thread.isMainThread; lock.unlock()
            started.signal()
            guard released.wait(timeout: .now() + 5) == .success else { throw Injected.failure }
            try data.write(to: url, options: .atomic)
        }
    }
}
