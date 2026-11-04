import SwiftUI
import SDWebImageSwiftUI

/// Only the cover and favorite thumbnail use this lifecycle boundary. Their
/// geometry and credits remain at the original call sites.
@MainActor
struct PreparedArticleImage: View {
    enum Style { case cover, favorite }
    enum Event { case preparing, loading(URL), loaded(URL), failed(URL?) }
    let articleID: String
    let revision: String?
    let remoteURL: URL?
    let style: Style
    let cache: OfflineArticleImageCache
    let event: ((Event) -> Void)?
    @ObservedObject private var offline = OfflineManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var refreshID = UUID()
    @State private var visible = false

    init(articleID: String, revision: String?, remoteURL: URL?, style: Style,
         cache: OfflineArticleImageCache? = nil, event: ((Event) -> Void)? = nil) {
        self.articleID = articleID; self.revision = revision; self.remoteURL = remoteURL
        self.style = style; self.cache = cache ?? .shared; self.event = event
    }

    private struct Identity: Hashable {
        let articleID: String
        let revision: String?
        let remoteURL: URL?
        let contentKey: String?
        let lease: UUID?
        let online: Bool
        let cacheGeneration: UUID?
        let refresh: UUID
    }

    var body: some View {
        // Capture contains only live in-memory access checks, never file work.
        let access = cache.capturePreparationAccess(articleID: articleID, revision: revision)
        let generation = access.contentKey != nil && access.generation != nil ? cache.displayGeneration : nil
        let identity = Identity(articleID: articleID, revision: revision, remoteURL: remoteURL,
            contentKey: access.contentKey, lease: access.generation, online: offline.isOnline,
            cacheGeneration: generation, refresh: refreshID)
        PreparedRequest(remoteURL: remoteURL, access: access, generation: generation,
                        style: style, cache: cache, event: event)
            // Aspect-fill pixels may extend past the visible cover. Keep their
            // hit region within this prepared image's own layout bounds.
            .contentShape(Rectangle())
            .id(identity)
            .onAppear { visible = true }
            .onDisappear { visible = false }
            .onReceive(cache.displayChanges) { _ in
                // Unrelated offline-cache writes must not restart online images.
                let current = cache.capturePreparationAccess(articleID: articleID, revision: revision)
                if current.contentKey != nil, current.generation != nil, current.isCurrent() {
                    refreshID = cache.displayGeneration
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, visible { refreshID = UUID() }
            }
    }

    /// New input owns a new SwiftUI identity before its task starts. Results and
    /// image callbacks additionally retain their original request and access.
    private struct PreparedRequest: View {
        let remoteURL: URL?
        let access: OfflineArticleImageCache.PreparationAccess
        let generation: UUID?
        let style: Style
        let cache: OfflineArticleImageCache
        let event: ((Event) -> Void)?
        private struct Resolution { let id: UUID; let url: URL? }
        @State private var resolution: Resolution?
        @State private var operation = UUID()
        @State private var visible = false
        @State private var failed = false
        @State private var loaded = false

        private var isCurrent: Bool {
            guard generation.map({ cache.displayGeneration == $0 }) ?? true, access.isCurrent() else { return false }
            return generation.map({ cache.displayGeneration == $0 }) ?? true
        }
        private var radius: CGFloat { style == .cover ? 14 : 8 }
        private func options(for url: URL) -> SDWebImageOptions {
            var value: SDWebImageOptions = [.retryFailed, .continueInBackground, .scaleDownLargeImages]
            if style == .cover { value.insert(.highPriority) }
            // A revalidated file must not be concealed by a stale URL-keyed
            // decoded image after explicit cache eviction/replacement.
            if url.isFileURL { value.insert(.fromLoaderOnly) }
            return value
        }
        @ViewBuilder private var placeholder: some View {
            if failed || (resolution != nil && resolution?.url == nil) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.quaternary)
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                            if style == .cover {
                                Text("Billedet kunne ikke vises")
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .foregroundStyle(.secondary)
                        .padding(12)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Billedet kunne ikke vises")
                    .accessibilityIdentifier(style == .cover ? "articleImage.coverFailure" : "articleImage.favoriteFailure")
            } else {
                ArticleImagePlaceholder(mode: .loading, cornerRadius: radius)
            }
        }
        var body: some View {
            // Reserve the cover's existing maximum slot before bytes arrive.
            // An image's intrinsic ratio must not move the credit/body on load
            // or failure. The favorite's existing 80pt parent owns its size.
            placeholder
                .frame(idealHeight: style == .cover ? 340 : nil)
                .overlay {
                if isCurrent, let resolution, let url = resolution.url, !failed {
                    WebImage(url: url, options: options(for: url))
                        .onSuccess { _, _, _ in
                            Task { @MainActor in
                                guard visible, isCurrent, operation == resolution.id, !failed, !loaded else { return }
                                loaded = true
                                event?(.loaded(url))
                            }
                        }
                        .onFailure { _ in
                            Task { @MainActor in
                                guard visible, isCurrent, operation == resolution.id, !failed, !loaded else { return }
                                failed = true
                                event?(.failed(url))
                            }
                        }
                        .resizable()
                        .transition(.identity)
                        .aspectRatio(contentMode: .fill)
                        .id(resolution.id)
                }
            }
            .task {
                let id = UUID()
                operation = id; visible = true; resolution = nil; failed = false; loaded = false
                guard !Task.isCancelled, isCurrent else { return }
                event?(.preparing)
                let url = await cache.prepareDisplayURL(for: remoteURL, access: access, force: true)
                guard !Task.isCancelled, visible, isCurrent, operation == id else { return }
                resolution = Resolution(id: id, url: url)
                if let url { event?(.loading(url)) }
                else { event?(.failed(nil)) }
            }
            .onDisappear {
                visible = false; operation = UUID(); resolution = nil
            }
        }
    }
}
