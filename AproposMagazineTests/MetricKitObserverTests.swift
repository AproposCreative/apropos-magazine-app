import Foundation
import XCTest
#if canImport(MetricKit)
import MetricKit
@testable import Apropos

final class MetricKitObserverTests: XCTestCase {
    @MainActor
    func testDeniedOrUnknownConsentCannotStartSystemRegistration() {
        let f = DiagnosticFixture(), model = f.configure()
        var added: [MXMetricManagerSubscriber] = [], removed: [MXMetricManagerSubscriber] = []
        let observer = MetricKitObserver(add: { added.append($0) }, remove: { removed.append($0) })
        observer.configure(model: model, now: { f.clock })
        XCTAssertTrue(added.isEmpty)
        XCTAssertTrue(removed.isEmpty)
        model.setChoices(.init(analyticsEnabled: true, diagnosticsEnabled: false))
        observer.configure(model: model, now: { f.clock })
        XCTAssertTrue(added.isEmpty)
    }

    @MainActor
    func testProxyIsStableForIdenticalChoiceAndRemovedExactlyAfterWithdrawal() throws {
        let f = DiagnosticFixture(), model = f.configure()
        var added: [MXMetricManagerSubscriber] = [], removed: [MXMetricManagerSubscriber] = []
        let observer = MetricKitObserver(add: { added.append($0) }, remove: { removed.append($0) })
        model.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        observer.configure(model: model, now: { f.clock })
        let first = try XCTUnwrap(added.first as? MetricKitObserver.Subscriber)
        observer.configure(model: model, now: { f.clock })
        XCTAssertEqual(added.count, 1)
        model.setChoices(.off)
        observer.configure(model: model, now: { f.clock })
        XCTAssertEqual(removed.count, 1)
        XCTAssertTrue((removed[0] as AnyObject) === first)
        observer.configure(model: model, now: { f.clock })
        XCTAssertEqual(removed.count, 1)
    }

    @MainActor
    func testOldProxyCannotPublishAfterReenableAndNewProxyRejectsEarlierIntervals() async throws {
        let f = DiagnosticFixture(), model = f.configure()
        var added: [MXMetricManagerSubscriber] = [], removed: [MXMetricManagerSubscriber] = []
        let observer = MetricKitObserver(add: { added.append($0) }, remove: { removed.append($0) })
        model.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        observer.configure(model: model, now: { f.clock })
        let old = try XCTUnwrap(added.last as? MetricKitObserver.Subscriber), firstDate = f.clock
        model.setChoices(.off)
        observer.configure(model: model, now: { f.clock })
        f.clock = f.clock.addingTimeInterval(10)
        model.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        observer.configure(model: model, now: { f.clock })
        let fresh = try XCTUnwrap(added.last as? MetricKitObserver.Subscriber), currentDate = f.clock
        XCTAssertFalse(old === fresh)
        old.recordProjectedCounts(["oom": 9], begin: firstDate, end: currentDate)
        fresh.recordProjectedCounts(["oom": 8], begin: firstDate, end: currentDate)
        fresh.recordProjectedCounts(["oom": 1], begin: currentDate, end: currentDate)
        for _ in 0..<120 { await Task.yield() }
        XCTAssertEqual(f.events, [.init(code: "metrickit_counts", measurements: ["oom": 1])])
        XCTAssertEqual(removed.count, 1)
    }

    @MainActor
    func testReentrantWithdrawalDuringRegistrationRemovesExactlyTheNewProxy() {
        let f = DiagnosticFixture(), model = f.configure()
        var added: [MXMetricManagerSubscriber] = [], removed: [MXMetricManagerSubscriber] = []
        let observer = MetricKitObserver(add: {
            added.append($0)
            _ = model.setChoices(.off)
        }, remove: { removed.append($0) })
        model.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        observer.configure(model: model, now: { f.clock })
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(removed.count, 1)
        XCTAssertTrue((added[0] as AnyObject) === (removed[0] as AnyObject))
        observer.configure(model: model, now: { f.clock })
        XCTAssertEqual(removed.count, 1)
    }

    @MainActor
    func testAccountContextReplacesTheSubscriberAndFencesItsQueuedProjection() async throws {
        let f = DiagnosticFixture(), model = f.configure()
        var added: [MXMetricManagerSubscriber] = [], removed: [MXMetricManagerSubscriber] = []
        let observer = MetricKitObserver(add: { added.append($0) }, remove: { removed.append($0) })
        model.setChoices(.init(analyticsEnabled: false, diagnosticsEnabled: true))
        observer.configure(model: model, now: { f.clock })
        let old = try XCTUnwrap(added.last as? MetricKitObserver.Subscriber)
        old.recordProjectedCounts(["crashes": 9], begin: f.clock, end: f.clock)
        model.changeContext(to: "new-account")
        observer.configure(model: model, now: { f.clock })
        let fresh = try XCTUnwrap(added.last as? MetricKitObserver.Subscriber)
        fresh.recordProjectedCounts(["crashes": 1], begin: f.clock, end: f.clock)
        for _ in 0..<120 { await Task.yield() }
        XCTAssertEqual(f.events, [.init(code: "metrickit_counts", measurements: ["crashes": 1])])
        XCTAssertTrue((removed[0] as AnyObject) === old)
    }
}
#endif
