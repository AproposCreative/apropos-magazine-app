import SwiftUI

/// Presentation of the existing collection state, not a per-article sync receipt.
enum FavoriteButtonStatus: Equatable {
    case ready, pending, issue, loading

    init(_ snapshot: FavoritesSnapshot) {
        switch snapshot.state {
        case .unresolved, .loading: self = .loading
        case .recovering: self = .pending
        default:
            if snapshot.issueMessage != nil { self = .issue }
            else if snapshot.state == .pending || !snapshot.pendingArticleIDs.isEmpty { self = .pending }
            else { self = .ready }
        }
    }

    var needsFeedback: Bool { self == .pending || self == .issue }
    var accessibilityValue: String {
        switch self {
        case .ready: return ""
        case .pending: return "Samlingen afventer bekræftelse"
        case .issue: return "Samlingen kræver opmærksomhed"
        case .loading: return "Samlingen indlæses"
        }
    }
}

/// Bind an action to the displayed intention as well as its original reader.
/// An old Remove action must never become Save after another control removed it.
struct FavoriteSelectionIntent: Equatable {
    let generation: UUID
    let articleID: String
    let selected: Bool

    init(snapshot: FavoritesSnapshot, articleID: String) {
        generation = snapshot.generation
        self.articleID = articleID
        selected = snapshot.articles.contains { $0.id == articleID }
    }

    func isCurrent(in snapshot: FavoritesSnapshot, articleID currentArticleID: String) -> Bool {
        generation == snapshot.generation && articleID == currentArticleID
            && selected == snapshot.articles.contains { $0.id == articleID }
            && FavoriteButtonStatus(snapshot) != .loading
    }
}

/// Used by the actual article header and the hermetic native fixture. It never
/// starts storage, downloads, Firebase or a new observer of remote data.
struct ArticleFavoriteControl: View {
    @ObservedObject var model: FavoritesModel
    let articleID: String
    let toggle: @MainActor (UUID) -> Void
    let retry: @MainActor (UUID) -> Void
    var requiresAccount = false
    var onAccountRequired: @MainActor () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var feedback: Feedback?

    private struct Feedback: Identifiable {
        let id = UUID()
        let generation: UUID
        let articleID: String
    }

    var body: some View {
        let intent = FavoriteSelectionIntent(snapshot: model.snapshot, articleID: articleID)
        let status = FavoriteButtonStatus(model.snapshot)
        Button {
            if requiresAccount { onAccountRequired(); return }
            guard intent.isCurrent(in: model.snapshot, articleID: articleID) else { return }
            // Check the live collection state too: a newly pending write must
            // not be treated as a confirmed toggle by an old rendered action.
            if FavoriteButtonStatus(model.snapshot).needsFeedback {
                feedback = Feedback(generation: intent.generation, articleID: articleID)
            } else if model.canChangeSelection { toggle(intent.generation) }
        } label: {
            ZStack {
                Circle().fill(Color.gray.opacity(0.1)).frame(width: 32, height: 32)
                Image(systemName: symbol(status, selected: intent.selected))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 16, height: 16)
            }
        }
        .disabled(!requiresAccount && (status == .loading || (!status.needsFeedback && !model.canChangeSelection)))
        .accessibilityIdentifier("favorite.control")
        .accessibilityLabel(LocalizedStringKey(requiresAccount ? "Gem artikel" : status.needsFeedback ? "Status for gemte artikler" : (intent.selected ? "Fjern fra gemte artikler" : "Gem artikel")))
        .accessibilityValue([model.canChangeSelection ? (intent.selected ? "Valgt" : "Ikke valgt") : "Valg endnu ukendt", status.accessibilityValue].filter { !$0.isEmpty }.map {
            AppLocalization.string($0, language: AppLocalization.language(for: locale))
        }.joined(separator: ". "))
        .accessibilityHint(LocalizedStringKey(requiresAccount ? "Log ind eller opret en konto for at gemme artiklen." : status.needsFeedback ? "Se status for samlingen, eller ændr dit valg for artiklen." : ""))
        .sheet(item: $feedback) { original in
            NavigationStack {
                ScrollView {
                    if original.generation == model.snapshot.generation && original.articleID == articleID {
                        feedbackContent(original)
                    }
                }
                .navigationTitle("Din samling")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Luk") { feedback = nil }
                            .accessibilityIdentifier("favorite.close")
                    }
                }
            }
            .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: model.snapshot.generation) { _, _ in feedback = nil }
        .onChange(of: articleID) { _, _ in feedback = nil }
    }

    private func feedbackContent(_ original: Feedback) -> some View {
        let intent = FavoriteSelectionIntent(snapshot: model.snapshot, articleID: articleID)
        return VStack(alignment: .leading, spacing: 16) {
            Text(LocalizedStringKey(!model.canChangeSelection ? "Artiklens valg kan ikke vises, før dine gemte artikler er indlæst." : (intent.selected ? "Denne artikel er valgt i din samling." : "Denne artikel er ikke valgt i din samling.")))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("favorite.selectionStatus")
            FavoritesNotice(model: model) { generation in
                guard original.generation == generation, original.articleID == articleID,
                      model.snapshot.generation == generation else { return }
                retry(generation)
            }
            Button(LocalizedStringKey(intent.selected ? "Fjern fra gemte artikler" : "Gem artikel")) {
                guard original.generation == intent.generation, original.articleID == articleID,
                      intent.isCurrent(in: model.snapshot, articleID: articleID), model.canChangeSelection else { return }
                toggle(intent.generation)
            }
            .buttonStyle(.bordered)
            .tint(.primary)
            .disabled(!model.canChangeSelection)
            .accessibilityIdentifier("favorite.selection")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func symbol(_ status: FavoriteButtonStatus, selected: Bool) -> String {
        switch status {
        case .pending: return "clock"
        case .issue: return "exclamationmark"
        case .ready, .loading: return selected ? "checkmark" : "plus"
        }
    }
}
