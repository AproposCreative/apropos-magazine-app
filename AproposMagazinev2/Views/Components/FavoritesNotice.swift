import SwiftUI

/// Shared production feedback. A cached list and a provider receipt are distinct
/// states; an action captured in this notice cannot retry a later owner.
struct FavoritesNotice: View {
    @ObservedObject var model: FavoritesModel
    var deferPendingFeedback = false
    let retry: @MainActor (UUID) -> Void
    @Environment(\.deferredFavoritesPendingGeneration) private var revealedPending

    // Ordinary journal/metadata receipts can be pending for a single frame.
    // Revisions within one pending window must not postpone persistent feedback.
    private var pendingGeneration: UUID? {
        guard deferPendingFeedback, model.snapshot.issueMessage == nil,
              FavoriteButtonStatus(model.snapshot) == .pending else { return nil }
        return model.snapshot.generation
    }
    private var showsFeedback: Bool {
        FavoriteButtonStatus(model.snapshot).needsFeedback
            && (pendingGeneration == nil || revealedPending == pendingGeneration)
    }

    var body: some View {
        Group {
            if showsFeedback {
                let generation = model.snapshot.generation
                VStack(alignment: .leading, spacing: 10) {
                    Label("Gemte artikler", systemImage: "bookmark")
                        .font(.headline)
                    Text(model.snapshot.issueMessage ?? "Ændringer i dine gemte artikler afventer bekræftelse. Dine valg vises imens.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("favorites.issue")
                    if model.snapshot.canRetry {
                        Button("Prøv igen") {
                            guard model.snapshot.generation == generation else { return }
                            retry(generation)
                        }
                        .tint(.primary)
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("favorites.retry")
                    }
                }
                .foregroundStyle(.primary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .contain)
                .modifier(FavoritesNoticeProbe())
            }
        }
    }
}

/// The list exists even when the conditional notice is empty. Own the waiting
/// task here so a sustained pending state can actually mount its first card.
private struct DeferredFavoritesNotice: ViewModifier {
    @ObservedObject var model: FavoritesModel
    @Environment(\.minSidePageIsVisible) private var pageIsVisible
    @State private var revealedPending: UUID?
    private var pendingGeneration: UUID? {
        guard pageIsVisible, model.snapshot.issueMessage == nil,
              FavoriteButtonStatus(model.snapshot) == .pending else { return nil }
        return model.snapshot.generation
    }
    func body(content: Content) -> some View {
        content.environment(\.deferredFavoritesPendingGeneration, revealedPending)
            .onChange(of: pendingGeneration) { _, _ in revealedPending = nil }
            .task(id: pendingGeneration) {
                revealedPending = nil
                guard let generation = pendingGeneration else { return }
                do { try await Task.sleep(for: .milliseconds(600)) }
                catch { return }
                guard !Task.isCancelled, pendingGeneration == generation else { return }
                revealedPending = generation
            }
            .onDisappear { revealedPending = nil }
    }
}
private struct DeferredFavoritesPendingKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}
extension EnvironmentValues {
    fileprivate var deferredFavoritesPendingGeneration: UUID? {
        get { self[DeferredFavoritesPendingKey.self] }
        set { self[DeferredFavoritesPendingKey.self] = newValue }
    }
}
extension View {
    func deferBriefFavoritesFeedback(model: FavoritesModel) -> some View {
        modifier(DeferredFavoritesNotice(model: model))
    }
}

// Read-only simulator observations of the actual card, never product controls.
private struct FavoritesNoticeProbe: ViewModifier {
    #if DEBUG && targetEnvironment(simulator)
    @Environment(\.favoritesNoticeVisibilityProbe) private var visibility
    @Environment(\.favoritesNoticeFrameProbe) private var frame
    #endif
    @ViewBuilder func body(content: Content) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        content.onAppear { visibility?(true) }
            .onDisappear { visibility?(false) }
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame?($0) }
        #else
        content
        #endif
    }
}
#if DEBUG && targetEnvironment(simulator)
private struct FavoritesNoticeVisibilityKey: EnvironmentKey {
    static let defaultValue: ((Bool) -> Void)? = nil
}
private struct FavoritesNoticeFrameKey: EnvironmentKey {
    static let defaultValue: ((CGRect) -> Void)? = nil
}
extension EnvironmentValues {
    var favoritesNoticeVisibilityProbe: ((Bool) -> Void)? {
        get { self[FavoritesNoticeVisibilityKey.self] }
        set { self[FavoritesNoticeVisibilityKey.self] = newValue }
    }
    var favoritesNoticeFrameProbe: ((CGRect) -> Void)? {
        get { self[FavoritesNoticeFrameKey.self] }
        set { self[FavoritesNoticeFrameKey.self] = newValue }
    }
}
#endif
