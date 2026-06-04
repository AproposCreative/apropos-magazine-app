import Foundation
import OSLog

enum AppDiagnostics {
    private static let logger = Logger(subsystem: "com.aproposmagazine.app", category: "Diagnostics")
    private static let breadcrumbsKey = "diagnostics_breadcrumbs_v1"
    private static let maxEntries = 80

    static func breadcrumb(_ message: String) {
        logger.log("\(message, privacy: .public)")
        var entries = UserDefaults.standard.stringArray(forKey: breadcrumbsKey) ?? []
        let stamp = ISO8601DateFormatter().string(from: Date())
        entries.append("[\(stamp)] \(message)")
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        UserDefaults.standard.set(entries, forKey: breadcrumbsKey)
    }

    static func recentBreadcrumbs() -> [String] {
        UserDefaults.standard.stringArray(forKey: breadcrumbsKey) ?? []
    }
}
