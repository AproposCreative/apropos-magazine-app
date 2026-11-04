import XCTest
@testable import Apropos

final class AppReadinessTests: XCTestCase {
    @MainActor
    func testTimeoutReturnsWithoutUIEverAppearing() async {
        let gate = UIReadinessGate()
        let finished = expectation(description: "Readiness timeout returns")
        let task = Task {
            await gate.wait(timeout: 0.01)
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)
        // Release a broken implementation too, so failed tests cannot hang.
        gate.markReady()
        await task.value
    }

    @MainActor
    func testReadyResumesAllWaitersAndAllowsFutureWaits() async {
        let gate = UIReadinessGate()
        let first = Task { await gate.wait(timeout: 30) }
        let second = Task { await gate.wait(timeout: 30) }
        await Task.yield()
        gate.markReady()
        await first.value
        await second.value
        await gate.wait(timeout: 30)
        gate.markReady()
    }

    @MainActor
    func testCancellationReturnsWithoutUIOrDeadline() async {
        let gate = UIReadinessGate()
        let finished = expectation(description: "Cancelled readiness wait returns")
        let task = Task {
            await gate.wait(timeout: 30)
            finished.fulfill()
        }
        await Task.yield()
        task.cancel()
        await fulfillment(of: [finished], timeout: 2)
        gate.markReady()
        await task.value
    }
}
