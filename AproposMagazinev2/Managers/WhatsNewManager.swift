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

    /// Entries relevant for the currently installed app version.
    func entriesForDisplay() -> [WhatsNewEntry] {
        let relevant = entries
            .filter { compare($0.version, currentVersion) != .orderedDescending }
            .sorted { compare($0.version, $1.version) == .orderedDescending }

        if !relevant.isEmpty {
            return relevant
        }

        if let generated = Self.loadEntryFromBundledChangelog(currentVersion: currentVersion) {
            return [generated]
        }

        return entries.sorted { compare($0.version, $1.version) == .orderedDescending }
    }

    func entryToPresent() -> WhatsNewEntry? {
        guard let entry = entriesForDisplay().first else {
            return nil
        }

        if shouldDisplay(entry.version) {
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
        guard let entry = entriesForDisplay().first else { return false }
        return shouldDisplay(entry.version)
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
            var entries = try decoder.decode([WhatsNewEntry].self, from: data)

            // Auto-generate latest entry from bundled CHANGELOG when available.
            // This keeps "latest improvements" up to date without manual JSON edits.
            let currentVersion = Bundle.main.shortVersionString
            if let generated = loadEntryFromBundledChangelog(currentVersion: currentVersion) {
                entries.removeAll { $0.version == generated.version }
                entries.insert(generated, at: 0)
            }

            return entries
        } catch {
            let logger = Logger(subsystem: "com.aproposmagazine.app", category: "WhatsNewManager")
            logger.error("Kunne ikke loade WhatsNew data: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private static func loadEntryFromBundledChangelog(currentVersion: String) -> WhatsNewEntry? {
        guard let changelogURL = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let markdown = try? String(contentsOf: changelogURL, encoding: .utf8) else {
            return nil
        }

        let extractedItems = extractItems(from: markdown).prefix(6).map { $0 }
        guard !extractedItems.isEmpty else { return nil }

        return WhatsNewEntry(
            version: currentVersion,
            title: "Nyheder i Apropos Magazine",
            subtitle: "Seneste forbedringer, automatisk hentet fra changelog.",
            items: extractedItems,
            ctaTitle: "Se hele changeloggen",
            ctaURL: URL(string: "https://aproposmagazine.com/changelog")
        )
    }

    private static func extractItems(from markdown: String) -> [WhatsNewItem] {
        let lines = markdown.components(separatedBy: .newlines)
        var items: [WhatsNewItem] = []

        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("- **"),
                  let title = parseTitle(from: line),
                  !title.isEmpty else {
                continue
            }

            var description = "Se den fulde changelog for flere detaljer."
            if index + 1 < lines.count {
                let nextLine = lines[index + 1].trimmingCharacters(in: .whitespaces)
                if nextLine.hasPrefix("- "), !nextLine.contains("**") {
                    description = String(nextLine.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            items.append(
                WhatsNewItem(
                    icon: iconFor("\(title) \(description)"),
                    title: title,
                    description: description
                )
            )
        }

        return items
    }

    private static func parseTitle(from bulletLine: String) -> String? {
        guard let start = bulletLine.range(of: "**"),
              let end = bulletLine.range(of: "**", options: [], range: start.upperBound..<bulletLine.endIndex) else {
            return nil
        }
        return String(bulletLine[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func iconFor(_ text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("fix") || lower.contains("bug") || lower.contains("fejl") {
            return "wrench.and.screwdriver.fill"
        }
        if lower.contains("notifikation") || lower.contains("notification") {
            return "bell.badge.fill"
        }
        if lower.contains("design") || lower.contains("ui") || lower.contains("glas") {
            return "wand.and.stars"
        }
        if lower.contains("performance") || lower.contains("hurtig") || lower.contains("speed") || lower.contains("optimer") {
            return "bolt.fill"
        }
        if lower.contains("search") || lower.contains("søg") || lower.contains("artikelsøgning") {
            return "magnifyingglass.circle.fill"
        }
        return "sparkles"
    }
}
