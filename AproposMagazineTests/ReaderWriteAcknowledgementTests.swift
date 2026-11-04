import XCTest
@testable import Apropos

final class ReaderWriteAcknowledgementTests: XCTestCase {
    @MainActor
    func testTimeoutEndsWaitAndLateOrDuplicateAcknowledgementIsHarmless() async {
        let fixture = WriteAcknowledgementFixture()
        let pending = Task { try await ReaderWriteAcknowledgement.perform(schedule: fixture.schedule, start: fixture.start) }
        await fixture.waitForStart()
        fixture.timeout?()
        let result = await pending.result
        guard case .failure(let error) = result else { return XCTFail("Expected unconfirmed write") }
        XCTAssertEqual((error as NSError).code, NSURLErrorTimedOut)
        fixture.completion?(nil)
        fixture.completion?(nil)
    }

    @MainActor
    func testServerAcknowledgementCancelsDeadlineAndIgnoresLateTimeout() async throws {
        let fixture = WriteAcknowledgementFixture()
        let pending = Task { try await ReaderWriteAcknowledgement.perform(schedule: fixture.schedule, start: fixture.start) }
        await fixture.waitForStart()
        fixture.completion?(nil)
        try await pending.value
        XCTAssertTrue(fixture.cancelled)
        fixture.timeout?()
    }

    @MainActor
    func testDrainingWaitSurvivesCancellationUntilActualProviderAcknowledgement() async throws {
        let fixture = WriteAcknowledgementFixture()
        var returned = false
        let pending = Task {
            try await ReaderWriteAcknowledgement.performDraining(start: fixture.start)
            returned = true
        }
        await fixture.waitForStart()
        pending.cancel()
        XCTAssertFalse(returned, "Cancellation must not refund the actual provider slot")
        XCTAssertNil(fixture.timeout, "Draining has no deadline that can counterfeit provider return")
        fixture.completion?(nil)
        try await pending.value
        XCTAssertTrue(returned)
        fixture.completion?(nil)
    }

    @MainActor
    func testImmediateDeadlineDoesNotStartAWriteAfterTimeout() async {
        var started = false
        do {
            try await ReaderWriteAcknowledgement.perform(schedule: { action in action(); return {} }) { _ in started = true }
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual((error as NSError).code, NSURLErrorTimedOut)
        }
        XCTAssertFalse(started)
    }
}

@MainActor
private final class WriteAcknowledgementFixture {
    var timeout: (() -> Void)?
    var completion: ((Error?) -> Void)?
    var cancelled = false
    private var observer: CheckedContinuation<Void, Never>?
    func schedule(_ timeout: @escaping () -> Void) -> () -> Void {
        self.timeout = timeout
        return { self.cancelled = true }
    }
    func start(_ completion: @escaping @Sendable (Error?) -> Void) {
        self.completion = completion
        observer?.resume()
        observer = nil
    }
    func waitForStart() async {
        if completion != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
}
