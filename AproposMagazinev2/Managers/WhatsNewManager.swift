import Foundation
import OSLog

final class WhatsNewManager {
    static let shared = WhatsNewManager()

    private let storageKey = "com.aproposmagazine.whatsnew.lastSeenVersion"
    private let logger = Logger(subsystem: "com.aproposmagazine.app", category: "WhatsNewManager")
    private let entries: [WhatsNewEntry]
    private let currentVersion: String

    private init() {
        currentVersion = Bundle.main.shortVersionString
        entries = WhatsNewManager.loadEntries()
    }

    func entryToPresent() -> WhatsNewEntry? {
        guard !entries.isEmpty else {
            return nil
        }

        let sortedEntries = entries.sorted { compare($0.version, $1.version) == .orderedDescending }
        
        // Find entry that matches current version or is the latest entry that's <= current version
        // If no entry matches, show the latest entry anyway (for new users)
        let candidate = sortedEntries.first(where: { compare($0.version, self.currentVersion) != .orderedDescending }) ?? sortedEntries.first

        guard let entry = candidate else {
            return nil
        }

        if self.shouldDisplay(entry.version) {
            return entry
        }

        return nil
    }
    
    /// Get all entries sorted by version (newest first)
    func getAllEntries() -> [WhatsNewEntry] {
        return entries.sorted { compare($0.version, $1.version) == .orderedDescending }
    }
    
    /// Check if we should show What's New (any entry not seen)
    func shouldShowWhatsNew() -> Bool {
        guard !entries.isEmpty else { return false }
        
        let sortedEntries = entries.sorted { compare($0.version, $1.version) == .orderedDescending }
        let latestEntry = sortedEntries.first
        
        guard let latest = latestEntry else { return false }
        
        return shouldDisplay(latest.version)
    }

    func markEntryAsSeen(_ entry: WhatsNewEntry) {
        UserDefaults.standard.set(entry.version, forKey: storageKey)
    }
    
    // MARK: - Testing Helper
    
    /// Reset last seen version (for testing)
    func resetLastSeenVersion() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
    
    // MARK: - Helpers

    private func shouldDisplay(_ version: String) -> Bool {
        let lastSeenVersion = UserDefaults.standard.string(forKey: storageKey)

        guard let lastSeenVersion else {
            // Nothing has been shown before
            return true
        }

        return compare(version, lastSeenVersion) == .orderedDescending
    }

    private func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsComponents = lhs.split(separator: ".").compactMap { Int($0) }
        let rhsComponents = rhs.split(separator: ".").compactMap { Int($0) }
        let maxCount = max(lhsComponents.count, rhsComponents.count)

        for index in 0..<maxCount {
            let left = index < lhsComponents.count ? lhsComponents[index] : 0
            let right = index < rhsComponents.count ? rhsComponents[index] : 0
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func loadEntries() -> [WhatsNewEntry] {
        // Try multiple paths to find the file
        var url: URL?
        
        // Try multiple paths to find the file in app bundle
        // Try with subdirectory first (most common)
        url = Bundle.main.url(forResource: "whatsnew", withExtension: "json", subdirectory: "Resources/WhatsNew")
        
        // Fallback: try without Resources prefix
        if url == nil {
            url = Bundle.main.url(forResource: "whatsnew", withExtension: "json", subdirectory: "WhatsNew")
        }
        
        // Fallback: try direct path
        if url == nil {
            url = Bundle.main.url(forResource: "whatsnew", withExtension: "json")
        }
        
        guard let fileURL = url else {
            let logger = Logger(subsystem: "com.aproposmagazine.app", category: "WhatsNewManager")
            logger.warning("Kunne ikke finde WhatsNew datafilen.")
            logger.debug("Tried paths: Resources/WhatsNew/whatsnew.json, WhatsNew/whatsnew.json, whatsnew.json")
            
            // Debug: List all JSON files in bundle
            if let bundlePath = Bundle.main.resourcePath {
                logger.debug("Bundle resource path: \(bundlePath, privacy: .public)")
                if let enumerator = FileManager.default.enumerator(atPath: bundlePath) {
                    let jsonFiles = enumerator.compactMap { $0 as? String }.filter { $0.contains("whatsnew") || $0.contains("WhatsNew") }
                    if !jsonFiles.isEmpty {
                        logger.debug("Found related files in bundle: \(jsonFiles.joined(separator: ", "), privacy: .public)")
                    }
                }
            }
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let entries = try decoder.decode([WhatsNewEntry].self, from: data)
            return entries
        } catch {
            let logger = Logger(subsystem: "com.aproposmagazine.app", category: "WhatsNewManager")
            logger.error("Kunne ikke loade WhatsNew data: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
