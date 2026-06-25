import Foundation
#if canImport(MetricKit)
import MetricKit
#endif

/// Surfaces the failure modes Crashlytics cannot see — most importantly OOM /
/// jetsam memory terminations and watchdog (unresponsive) terminations, which
/// are not signal-based crashes and therefore never appear in the Crashlytics
/// dashboard.
///
/// MetricKit delivers an aggregated payload roughly once every 24h covering the
/// previous day, so this is a near-zero-overhead background signal. We forward
/// the relevant exit counts to Crashlytics as breadcrumbs (always) and
/// non-fatals (when a memory/watchdog kill actually happened) so the data shows
/// up alongside everything else under "Non-fatals".
#if canImport(MetricKit)
final class MetricKitObserver: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricKitObserver()

    func start() {
        MXMetricManager.shared.add(self)
        AppDiagnostics.breadcrumb("metrickit_started")
    }

    // MARK: - Daily aggregated metrics (memory, exits, etc.)

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            guard let exit = payload.applicationExitMetrics else { continue }

            let fg = exit.foregroundExitData
            let bg = exit.backgroundExitData

            let oom = fg.cumulativeMemoryResourceLimitExitCount
                + bg.cumulativeMemoryResourceLimitExitCount
            let watchdog = fg.cumulativeAppWatchdogExitCount
                + bg.cumulativeAppWatchdogExitCount
            let badAccess = fg.cumulativeBadAccessExitCount
                + bg.cumulativeBadAccessExitCount
            let abnormal = fg.cumulativeAbnormalExitCount
                + bg.cumulativeAbnormalExitCount
            let memoryPressure = bg.cumulativeMemoryPressureExitCount

            AppDiagnostics.breadcrumb(
                "metrickit_exits oom:\(oom) watchdog:\(watchdog) badaccess:\(badAccess) abnormal:\(abnormal) mempressure:\(memoryPressure)"
            )

            if oom > 0 {
                AppDiagnostics.recordError(
                    MetricKitExit.memoryTermination(count: oom),
                    context: "metrickit_oom"
                )
            }
            if watchdog > 0 {
                AppDiagnostics.recordError(
                    MetricKitExit.watchdogTermination(count: watchdog),
                    context: "metrickit_watchdog"
                )
            }
        }
    }

    // MARK: - Diagnostics (crash / hang / cpu / disk call stacks)

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let crashes = payload.crashDiagnostics?.count ?? 0
            let hangs = payload.hangDiagnostics?.count ?? 0
            let disk = payload.diskWriteExceptionDiagnostics?.count ?? 0
            let cpu = payload.cpuExceptionDiagnostics?.count ?? 0

            guard crashes + hangs + disk + cpu > 0 else { continue }
            AppDiagnostics.breadcrumb(
                "metrickit_diag crashes:\(crashes) hangs:\(hangs) disk:\(disk) cpu:\(cpu)"
            )
        }
    }
}

enum MetricKitExit: Error, LocalizedError {
    case memoryTermination(count: Int)
    case watchdogTermination(count: Int)

    var errorDescription: String? {
        switch self {
        case .memoryTermination(let count):
            return "App terminated by the OS for exceeding the memory limit (jetsam/OOM) ×\(count)"
        case .watchdogTermination(let count):
            return "App terminated by the watchdog (unresponsive / slow launch) ×\(count)"
        }
    }
}
#endif
