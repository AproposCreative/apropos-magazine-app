import Combine
import FirebaseCore
import XCTest
@testable import Apropos

/// Exercise the actual observable service at synchronous publication boundaries.
/// The injected transport never creates a Firestore reference or starts services.
@MainActor
final class SeriesStartupPublicationTests: XCTestCase {
    private enum Injected: LocalizedError {
        case failed
        var errorDescription: String? { "Local series failure" }
    }

    @MainActor private final class Gate {
        let entered: XCTestExpectation
        private var continuation: CheckedContinuation<Result<[ContentSeries], Error>, Never>?
        init(_ entered: XCTestExpectation) { self.entered = entered }
        func wait() async throws -> [ContentSeries] {
            let result: Result<[ContentSeries], Error> = await withCheckedContinuation { continuation in
                self.continuation = continuation
                self.entered.fulfill()
            }
            return try result.get()
        }
        func release(_ result: Result<[ContentSeries], Error>) {
            guard let continuation else { return XCTFail("No held Series transport") }
            self.continuation = nil
            continuation.resume(returning: result)
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }

    private func session(_ uid: String) -> ReaderAccountSession {
        .init(uid: uid, email: "reader@example.invalid", isEmailVerified: true)
    }
    private func series(_ id: String, time: TimeInterval = 0) -> ContentSeries {
        .init(slug: id, name: id, description: "Local", articleIds: [], generatedAt: Date(timeIntervalSince1970: time))
    }

    func testAccountRoundTripInsideSeriesNotificationCannotCommitOldResult() async {
        let identity = CanonicalSessionState()
        _ = identity.adopt(session("A"))
        let context = identity.contextTicket()
        let gate = Gate(expectation(description: "Series response held"))
        let service = SeriesService(transport: { _ in try await gate.wait() })
        let task = Task { @MainActor in await service.fetchSeries(stillCurrent: { identity.isCurrent(context) }) }
        await fulfillment(of: [gate.entered], timeout: 3)
        var reentered = false
        let observer = service.objectWillChange.sink { [self] in
            guard !reentered else { return }
            reentered = true
            XCTAssertTrue(service.series.isEmpty)
            _ = identity.adopt(self.session("B")); _ = identity.adopt(self.session("A"))
        }
        gate.release(.success([series("old")]))
        await task.value
        XCTAssertTrue(reentered); XCTAssertTrue(service.series.isEmpty)
        XCTAssertNil(service.errorMessage); XCTAssertFalse(service.isLoading)
        withExtendedLifetime(observer) {}
    }

    func testAccountRoundTripInsideFailureNotificationCannotCommitOldError() async {
        let identity = CanonicalSessionState()
        _ = identity.adopt(session("A"))
        let context = identity.contextTicket()
        let gate = Gate(expectation(description: "Series failure held"))
        let service = SeriesService(transport: { _ in try await gate.wait() })
        let task = Task { @MainActor in await service.fetchSeries(stillCurrent: { identity.isCurrent(context) }) }
        await fulfillment(of: [gate.entered], timeout: 3)
        var reentered = false
        let observer = service.objectWillChange.sink { [self] in
            guard !reentered else { return }
            reentered = true
            XCTAssertNil(service.errorMessage)
            _ = identity.adopt(self.session("B")); _ = identity.adopt(self.session("A"))
        }
        gate.release(.failure(Injected.failed))
        await task.value
        XCTAssertTrue(reentered); XCTAssertNil(service.errorMessage)
        XCTAssertTrue(service.series.isEmpty); XCTAssertFalse(service.isLoading)
        withExtendedLifetime(observer) {}
    }

    func testRevocationDuringErrorClearPreservesPreviousErrorAndDoesNotStartTransport() async {
        var calls = 0, permitted = true
        let service = SeriesService(transport: { _ in calls += 1; throw Injected.failed })
        await service.fetchSeries(stillCurrent: { permitted })
        XCTAssertEqual(service.errorMessage, "Local series failure"); XCTAssertEqual(calls, 1)
        var reentered = false
        let observer = service.objectWillChange.sink {
            // isLoading's initial willSet still exposes false. The next
            // notification is the attempted clear of the previous error.
            guard service.isLoading, !reentered else { return }
            reentered = true
            permitted = false
        }
        await service.fetchSeries(stillCurrent: { permitted })
        XCTAssertTrue(reentered); XCTAssertEqual(calls, 1)
        XCTAssertEqual(service.errorMessage, "Local series failure")
        XCTAssertFalse(service.isLoading)
        withExtendedLifetime(observer) {}
    }

    func testCurrentResultNotifiesBeforeCommitAndPreservesSorting() async {
        let gate = Gate(expectation(description: "Current Series response held"))
        let service = SeriesService(transport: { _ in try await gate.wait() })
        let task = Task { @MainActor in await service.fetchSeries(stillCurrent: { true }) }
        await fulfillment(of: [gate.entered], timeout: 3)
        var observed: [[String]] = []
        let observer = service.objectWillChange.sink { observed.append(service.series.map(\.slug)) }
        gate.release(.success([series("older", time: 1), series("newer", time: 2)]))
        await task.value
        XCTAssertEqual(observed.first, [])
        XCTAssertEqual(service.series.map(\.slug), ["newer", "older"])
        XCTAssertEqual(observed.last, ["newer", "older"])
        XCTAssertNil(service.errorMessage); XCTAssertFalse(service.isLoading)
        withExtendedLifetime(observer) {}
    }
}
