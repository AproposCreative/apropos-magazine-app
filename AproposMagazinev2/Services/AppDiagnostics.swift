import Foundation
import OSLog

#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

enum AppDiagnostics {
    private static let logger = Logger(subsystem: "com.aproposmagazine.app", category: "Diagnostics")
    private static let breadcrumbsKey = "diagnostics_breadcrumbs_v1"
    private static let maxEntries = 80

    /// Records a lightweight breadcrumb to OSLog, local storage, and (when linked)
    /// Crashlytics so the trail survives a crash and is attached to the next report.
    static func breadcrumb(_ message: String) {
        logger.log("\(message, privacy: .public)")
        var entries = UserDefaults.standard.stringArray(forKey: breadcrumbsKey) ?? []
        let stamp = ISO8601DateFormatter().string(from: Date())
        entries.append("[\(stamp)] \(message)")
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        UserDefaults.standard.set(entries, forKey: breadcrumbsKey)

        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().log(message)
        #endif
    }

    static func recentBreadcrumbs() -> [String] {
        UserDefaults.standard.stringArray(forKey: breadcrumbsKey) ?? []
    }

    /// Non-fatal error reporting. Adds an optional context breadcrumb and forwards
    /// the error to Crashlytics so it shows up under "Non-fatals" in the console.
    static func recordError(_ error: Error, context: String? = nil) {
        if let context {
            breadcrumb("error:\(context):\(error.localizedDescription)")
        } else {
            breadcrumb("error:\(error.localizedDescription)")
        }

        #if canImport(FirebaseCrashlytics)
        if let context {
            Crashlytics.crashlytics().setCustomValue(context, forKey: "error_context")
        }
        Crashlytics.crashlytics().record(error: error)
        #endif
    }

    /// Associates the current authenticated user with crash reports (no PII beyond the id).
    static func setUserIdentifier(_ identifier: String?) {
        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().setUserID(identifier ?? "")
        #endif
    }
}
