import Foundation

/// The actual custom/universal delegate and scene entry adapter, with injected
/// effects. Construction, parsing and rejected inputs never initialize services.
@MainActor
final class IncomingLinkEntry {
    private let disabled: Bool
    private let handleGoogle: @MainActor (URL) -> Bool
    private let accept: @MainActor (URL) -> Bool

    init(disabled: Bool, handleGoogle: @escaping @MainActor (URL) -> Bool,
         accept: @escaping @MainActor (URL) -> Bool) {
        self.disabled = disabled
        self.handleGoogle = handleGoogle
        self.accept = accept
    }

    func openURL(_ url: URL) -> Bool {
        guard !disabled else { return false }
        if handleGoogle(url) { return true }
        guard DeepLink.parse(url) != nil else { return false }
        return accept(url)
    }

    func continueActivity(type: String, webpageURL: URL?) -> Bool {
        guard !disabled, type == NSUserActivityTypeBrowsingWeb, let url = webpageURL,
              url.scheme?.lowercased() == "https", DeepLink.parse(url) != nil else { return false }
        return accept(url)
    }
}
