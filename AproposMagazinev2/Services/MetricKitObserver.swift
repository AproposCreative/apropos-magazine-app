import Foundation
#if canImport(MetricKit)
import MetricKit

/// Each registration owns one immutable consent/context ticket and interval.
/// Old subscriber callbacks can never adopt a newer opt-in or account context.
@MainActor
final class MetricKitObserver {
    typealias Registration = @MainActor (MXMetricManagerSubscriber) -> Void
    static let shared = MetricKitObserver(add: { MXMetricManager.shared.add($0) }, remove: { MXMetricManager.shared.remove($0) })
    private let add: Registration
    private let remove: Registration
    private var subscriber: Subscriber?

    /// Tests inject inert registration closures. Merely creating an observer does
    /// not instantiate or subscribe to MXMetricManager.
    init(add: @escaping Registration, remove: @escaping Registration) {
        self.add = add
        self.remove = remove
    }

    func configure(model: TelemetryConsentModel, now: @escaping @Sendable () -> Date) {
        guard let ticket = model.captureTicket(for: .diagnostics) else {
            if let old = subscriber { remove(old) }
            subscriber = nil
            return
        }
        if let old = subscriber, old.model === model, old.ticket == ticket { return }
        if let old = subscriber { remove(old) }
        subscriber = nil
        let since = now()
        guard since.timeIntervalSince1970.isFinite, since.timeIntervalSince1970 > 0 else { return }
        // Recheck after a reentrant clock/registration hook before starting a subscription.
        model.withPermission(ticket, for: .diagnostics) {
            let proxy = Subscriber(model: model, ticket: ticket, since: since, now: now)
            subscriber = proxy
            add(proxy)
            if !model.withPermission(ticket, for: .diagnostics, perform: {}), subscriber === proxy {
                subscriber = nil
                remove(proxy)
            }
        }
    }

    final class Subscriber: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
        let model: TelemetryConsentModel
        let ticket: TelemetryConsentModel.Ticket
        private let since: Date
        private let now: @Sendable () -> Date
        init(model: TelemetryConsentModel, ticket: TelemetryConsentModel.Ticket, since: Date,
             now: @escaping @Sendable () -> Date) {
            self.model = model
            self.ticket = ticket
            self.since = since
            self.now = now
        }

        func didReceive(_ payloads: [MXMetricPayload]) {
            for payload in payloads.prefix(32) {
                guard let exit = payload.applicationExitMetrics,
                      let oom = boundedSum(exit.foregroundExitData.cumulativeMemoryResourceLimitExitCount, exit.backgroundExitData.cumulativeMemoryResourceLimitExitCount),
                      let watchdog = boundedSum(exit.foregroundExitData.cumulativeAppWatchdogExitCount, exit.backgroundExitData.cumulativeAppWatchdogExitCount),
                      let badAccess = boundedSum(exit.foregroundExitData.cumulativeBadAccessExitCount, exit.backgroundExitData.cumulativeBadAccessExitCount),
                      let abnormal = boundedSum(exit.foregroundExitData.cumulativeAbnormalExitCount, exit.backgroundExitData.cumulativeAbnormalExitCount),
                      let memoryPressure = Int(exactly: exit.backgroundExitData.cumulativeMemoryPressureExitCount) else { continue }
                recordProjectedCounts(["oom": oom, "watchdog": watchdog, "badaccess": badAccess,
                                       "abnormal": abnormal, "memory_pressure": memoryPressure], begin: payload.timeStampBegin, end: payload.timeStampEnd)
            }
        }

        func didReceive(_ payloads: [MXDiagnosticPayload]) {
            for payload in payloads.prefix(32) {
                // Only array counts are projected. Never retain call stacks, SDK
                // payloads, JSON representations, error text or diagnostic objects.
                recordProjectedCounts(["crashes": payload.crashDiagnostics?.count ?? 0, "hangs": payload.hangDiagnostics?.count ?? 0,
                                       "disk": payload.diskWriteExceptionDiagnostics?.count ?? 0, "cpu": payload.cpuExceptionDiagnostics?.count ?? 0],
                                      begin: payload.timeStampBegin, end: payload.timeStampEnd)
            }
        }

        /// The same post-projection path is available to inert subscriber tests.
        func recordProjectedCounts(_ counts: [String: Int], begin: Date, end: Date) {
            guard TelemetryDiagnosticPolicy.metrics(counts) != nil,
                  TelemetryDiagnosticPolicy.permitsInterval(begin: begin, end: end, since: since, now: now()) else { return }
            AppDiagnostics.recordMetricCounts(counts, begin: begin, end: end, since: since, ticket: ticket, model: model)
        }

        private func boundedSum<T: BinaryInteger>(_ left: T, _ right: T) -> Int? {
            guard let first = Int(exactly: left), let second = Int(exactly: right), (0...1_000_000).contains(first),
                  (0...1_000_000).contains(second), first <= 1_000_000 - second else { return nil }
            return first + second
        }
    }
}
#endif
