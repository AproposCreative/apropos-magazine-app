import XCTest
@testable import Apropos

@MainActor
final class ReaderNewsletterCredentialDeadlineTests: XCTestCase {
    private typealias Deadline = ReaderNewsletterCredentialDeadline
    private enum TestFailure: Error, Equatable { case token, clock }

    /// Deliberately ignores cancellation, just like an SDK completion callback.
    @MainActor private final class Suspended<Value: Sendable> {
        private(set) var started = false
        private var continuation: CheckedContinuation<Value, Error>?
        func wait() async throws -> Value {
            started = true
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        func finish(_ value: Value) { continuation?.resume(returning: value); continuation = nil }
        func fail(_ error: Error) { continuation?.resume(throwing: error); continuation = nil }
    }

    private func eventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Expected local continuation state was not reached", file: file, line: line)
    }

    func testSuccessfulTokenReturnsBeforeAnUncooperativeTimerAndLateExpiryIsIgnored() async throws {
        let token = Suspended<String>(), clock = Suspended<Void>()
        var configuredTimeout: UInt64?
        let call = Task {
            try await Deadline.run(timeoutNanoseconds: 123, sleep: { duration in
                configuredTimeout = duration
                try await clock.wait()
            }, operation: { try await token.wait() })
        }
        await eventually { token.started && clock.started }
        token.finish("accepted-token")
        let result = try await call.value
        XCTAssertEqual(result, "accepted-token")
        XCTAssertEqual(configuredTimeout, 123)
        clock.finish(())
        await Task.yield()
    }

    func testTokenFailureIsReturnedAndLaterClockFailureCannotResumeAgain() async {
        let token = Suspended<String>(), clock = Suspended<Void>()
        let call = Task { try await Deadline.run(sleep: { _ in try await clock.wait() }, operation: { try await token.wait() }) }
        await eventually { token.started && clock.started }
        token.fail(TestFailure.token)
        do { _ = try await call.value; XCTFail("Expected token failure") }
        catch { XCTAssertEqual(error as? TestFailure, .token) }
        clock.fail(TestFailure.clock)
        await Task.yield()
    }

    func testTimeoutReleasesCallerBeforeUncooperativeTokenReturnsAndIgnoresLateSuccess() async {
        let token = Suspended<String>(), clock = Suspended<Void>()
        let call = Task { try await Deadline.run(sleep: { _ in try await clock.wait() }, operation: { try await token.wait() }) }
        await eventually { token.started && clock.started }
        clock.finish(())
        do { _ = try await call.value; XCTFail("Expected timeout before releasing the token callback") }
        catch { XCTAssertEqual(error as? Deadline.Failure, .timedOut) }
        token.finish("too-late-token")
        await Task.yield()
    }

    func testCancellationReleasesCallerWithoutWaitingAndIgnoresLateTokenFailure() async {
        let token = Suspended<String>(), clock = Suspended<Void>()
        let call = Task { try await Deadline.run(sleep: { _ in try await clock.wait() }, operation: { try await token.wait() }) }
        await eventually { token.started && clock.started }
        call.cancel()
        do { _ = try await call.value; XCTFail("Expected cancellation before releasing either callback") }
        catch { XCTAssertTrue(error is CancellationError) }
        token.fail(TestFailure.token)
        clock.finish(())
        await Task.yield()
    }

    func testAlreadyCancelledCallerStartsNeitherSDKOperationNorTimer() async {
        var operationCalls = 0, timerCalls = 0
        let call = Task { @MainActor in
            try await Deadline.run(sleep: { _ in timerCalls += 1 }, operation: {
                operationCalls += 1
                return "unexpected"
            })
        }
        call.cancel()
        do { _ = try await call.value; XCTFail("Expected immediate cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(operationCalls, 0)
        XCTAssertEqual(timerCalls, 0)
    }

    func testUnreturnedTimedOutCallDoesNotHoldTheNextCallsCredentialSlot() async throws {
        let firstToken = Suspended<String>(), firstClock = Suspended<Void>()
        let first = Task { try await Deadline.run(sleep: { _ in try await firstClock.wait() }, operation: { try await firstToken.wait() }) }
        await eventually { firstToken.started && firstClock.started }
        firstClock.finish(())
        do { _ = try await first.value; XCTFail("Expected first timeout") }
        catch { XCTAssertEqual(error as? Deadline.Failure, .timedOut) }

        let secondToken = Suspended<String>(), secondClock = Suspended<Void>()
        let second = Task { try await Deadline.run(sleep: { _ in try await secondClock.wait() }, operation: { try await secondToken.wait() }) }
        await eventually { secondToken.started && secondClock.started }
        firstToken.fail(TestFailure.token)
        secondToken.finish("fresh-token")
        let result = try await second.value
        XCTAssertEqual(result, "fresh-token")
        secondClock.finish(())
        await Task.yield()
    }

    func testCancelledOperationChecksCancellationBeforeStartingTheNextSDKStep() async {
        let firstSDK = Suspended<String>(), clock = Suspended<Void>()
        var secondSDKCalls = 0
        let call = Task {
            try await Deadline.run(sleep: { _ in try await clock.wait() }, operation: {
                _ = try await firstSDK.wait()
                try Task.checkCancellation()
                secondSDKCalls += 1
                return "second-token"
            })
        }
        await eventually { firstSDK.started && clock.started }
        clock.finish(())
        do { _ = try await call.value; XCTFail("Expected timeout") }
        catch { XCTAssertEqual(error as? Deadline.Failure, .timedOut) }
        firstSDK.finish("late-first-token")
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(secondSDKCalls, 0)
    }
}
