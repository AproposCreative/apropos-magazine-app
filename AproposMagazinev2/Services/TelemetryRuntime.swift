import Foundation
import FirebaseAnalytics
import FirebaseCrashlytics
import OSLog

/// The only production bridge to telemetry SDK controls. It is never prepared by
/// a unit-test host or a local simulator fixture. All consent/context mutations
/// in this bridge run on MainActor; SDK callbacks receive immutable tickets.
@MainActor
final class TelemetryRuntime {
    static let shared = TelemetryRuntime()
    private let disabled: Bool
    let model: TelemetryConsentModel
    private var sdkReady = false
    private var prepared = false
    private var applied: TelemetryConsentModel.Snapshot?
    lazy var controller = TelemetryConsentController(model: model) { [weak self] snapshot in
        self?.apply(snapshot)
    }
    private let defaults: DefaultsBridge?

    private init() {
        disabled = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || LocalSmokeMode.isEnabled
        if disabled {
            defaults = nil
            model = TelemetryConsentModel(storage: .init(read: { nil }, write: { _ in }), now: { Date() },
                                          sinks: .init(clearAnalytics: {}, clearDiagnostics: {}))
        } else {
            let bridge = DefaultsBridge()
            defaults = bridge
            model = TelemetryConsentModel(storage: .init(read: { try bridge.read() }, write: { try bridge.write($0) }), now: { Date() },
                                          sinks: .init(clearAnalytics: {
                                              MainActor.assumeIsolated { AnalyticsService.shared.clearTransientBuffers() }
                                          }, clearDiagnostics: { AppDiagnostics.clearBuffers() }))
        }
    }

    /// Call before Firebase.configure, without touching any Firebase API here.
    func prepare() {
        guard !disabled, !prepared, let defaults else { return }
        prepared = true
        let logger = Logger(subsystem: "com.aproposmagazine.app", category: "LocalDiagnostics")
        AppDiagnostics.configure(model: model, storage: .init(read: { defaults.breadcrumbs() }, write: { defaults.writeBreadcrumbs($0) }, clear: { defaults.clearBreadcrumbs() }), emit: { event in
            // Only policy-approved fixed codes and bounded counters reach OSLog.
            logger.log("\(event.code, privacy: .public)")
        }, now: { Date() })
        AnalyticsService.shared.configure(model: model)
        defaults.clearBreadcrumbs()
        model.load()
        controller.refresh()
    }

    /// Firebase can retain older runtime overrides. Setting false here and plist
    /// defaults cannot undo any upload selected before this call on an old install.
    /// Upgraded-device startup acceptance remains a release gate.
    func firebaseDidConfigure() {
        guard !disabled, prepared, !sdkReady else { return }
        sdkReady = true
        let crash = Crashlytics.crashlytics()
        crash.setCrashlyticsCollectionEnabled(false)
        crash.setUserID("")
        // Best effort while disabled; SDK exposes no purge-completion guarantee.
        crash.deleteUnsentReports()
        apply(model.snapshot())
    }

    /// Identifier is used only for local equality/fencing. It never reaches a sink.
    func changeAccountContext(to identifier: String?) {
        guard !disabled, prepared else { return }
        let snapshot = model.changeContext(to: identifier)
        controller.refresh()
        apply(snapshot)
    }

    private func apply(_ snapshot: TelemetryConsentModel.Snapshot) {
        guard !disabled, sdkReady, applied != snapshot else { return }
        applied = snapshot
        Analytics.setAnalyticsCollectionEnabled(false)
        Analytics.setConsent([.analyticsStorage: .denied, .adStorage: .denied, .adUserData: .denied, .adPersonalization: .denied])
        Analytics.setUserID(nil)
        Analytics.setDefaultEventParameters(nil)
        Analytics.resetAnalyticsData()
        if let ticket = model.captureTicket(for: .analytics) {
            model.withPermission(ticket, for: .analytics) {
                Analytics.setConsent([.analyticsStorage: .granted, .adStorage: .denied, .adUserData: .denied, .adPersonalization: .denied])
                Analytics.setAnalyticsCollectionEnabled(true)
            }
        }
        #if canImport(MetricKit)
        MetricKitObserver.shared.configure(model: model, now: { Date() })
        #endif
    }

    /// A readback verifies this process's stored value, not physical durability.
    private final class DefaultsBridge: @unchecked Sendable {
        private let defaults = UserDefaults.standard
        private let key = "telemetry_consent_v1"
        private let breadcrumbsKey = "diagnostics_breadcrumbs_v2"
        enum Failure: Error { case invalidStoredValue, writeReadback }
        func read() throws -> Data? {
            if defaults.object(forKey: key) != nil, defaults.data(forKey: key) == nil { throw Failure.invalidStoredValue }
            return defaults.data(forKey: key)
        }
        func write(_ data: Data) throws {
            defaults.set(data, forKey: key)
            guard defaults.data(forKey: key) == data else { throw Failure.writeReadback }
        }
        func breadcrumbs() -> [String] { defaults.stringArray(forKey: breadcrumbsKey) ?? [] }
        func writeBreadcrumbs(_ entries: [String]) { defaults.set(entries, forKey: breadcrumbsKey) }
        func clearBreadcrumbs() {
            defaults.removeObject(forKey: "diagnostics_breadcrumbs_v1")
            defaults.removeObject(forKey: breadcrumbsKey)
        }
    }
}
