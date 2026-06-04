import Foundation

enum PodcastAudioURLValidator {
    private static let blockedHosts = [
        "notebooklm.google.com",
        "accounts.google.com"
    ]

    static func isPlayableAudioURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if blockedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return false
        }

        if host == "google.com" || host.hasSuffix(".google.com") {
            return false
        }

        let path = url.path.lowercased()
        return path.hasSuffix(".mp3")
            || path.hasSuffix(".m4a")
            || path.hasSuffix(".aac")
            || path.hasSuffix(".wav")
            || path.hasSuffix(".mp4")
            || path.hasSuffix(".m3u8")
    }
}
