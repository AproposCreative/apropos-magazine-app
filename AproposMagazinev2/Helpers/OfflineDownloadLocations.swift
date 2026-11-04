import Foundation

/// Downloaded content survives ordinary cache eviction, but is reproducible and
/// must not enter an iCloud/device backup. Resolving a location performs no I/O.
enum OfflineDownloadLocations {
    private static var root: URL {
        URL.applicationSupportDirectory.appendingPathComponent("AproposMagazine", isDirectory: true)
    }
    private static var legacyRoot: URL {
        URL.cachesDirectory.appendingPathComponent("AproposMagazine", isDirectory: true)
    }
    static var audioDirectory: URL { root.appendingPathComponent("podcast-audio", isDirectory: true) }
    static var bodyDirectory: URL { root.appendingPathComponent("favorite-bodies-v1", isDirectory: true) }
    static var legacyAudioDirectory: URL { legacyRoot.appendingPathComponent("podcast-audio", isDirectory: true) }
    static var legacyBodyDirectory: URL { legacyRoot.appendingPathComponent("favorite-bodies-v1", isDirectory: true) }

    static func prepareDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard try FileManager.default.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType == .typeDirectory else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try configure(directory)
    }

    /// Copies/moves can retain the staging file's protection attributes. Apply
    /// the same storage policy before publishing the new content or receipt.
    static func prepareFile(_ file: URL) throws {
        guard try FileManager.default.attributesOfItem(atPath: file.path)[.type] as? FileAttributeType == .typeRegular else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try configure(file)
    }

    private static func configure(_ url: URL) throws {
        var location = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try location.setResourceValues(values)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }
}
