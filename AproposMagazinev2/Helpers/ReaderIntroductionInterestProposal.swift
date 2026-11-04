import Combine
import Foundation

/// Sheet-owned, memory-only suggestion. It observes the first signed-in epoch
/// even while the guest form is visible; no preference writes happen here.
@MainActor
final class ReaderIntroductionInterestProposal: ObservableObject {
    private struct Owner: Equatable {
        let userID: String
        let generation: UUID
    }
    nonisolated let objectWillChange = ObservableObjectPublisher()
    private let suggestedIDs: [String]
    private weak var canonical: CanonicalSessionState?
    private var firstOwner: Owner?
    private var invalidated = false
    private var observation: AnyCancellable?

    init(canonical: CanonicalSessionState, suggestedInterestTopicIDs: [String]?) {
        self.canonical = canonical
        suggestedIDs = Array(Set(suggestedInterestTopicIDs ?? [])).filter { !$0.isEmpty }.sorted()
        guard !suggestedIDs.isEmpty else { return }
        observe(canonical.snapshot)
        observation = canonical.changes.sink { [weak self] in self?.observe($0) }
    }

    private func observe(_ snapshot: CanonicalSessionState.Snapshot) {
        guard !invalidated else { return }
        if let firstOwner {
            guard snapshot.userID != firstOwner.userID || snapshot.generation != firstOwner.generation else { return }
            invalidated = true
            objectWillChange.send()
        } else if let id = snapshot.userID, snapshot.session?.uid == id {
            firstOwner = Owner(userID: id, generation: snapshot.generation)
            objectWillChange.send()
        }
    }

    func topicIDs(context: CanonicalSessionState.ContextTicket, topics: [Topic]) -> [String] {
        guard !invalidated, let canonical, canonical.isCurrent(context), let firstOwner,
              context.userID == firstOwner.userID, context.generation == firstOwner.generation else { return [] }
        let actualIDs = Set(topics.filter(\.isActive).map(\.id))
        return Array(suggestedIDs.filter { actualIDs.contains($0) }.prefix(20))
    }

    /// The button may only change the draft already adopted by the current form.
    /// A pending/error/newer load must not be mistaken for that accepted draft.
    func draftTopicIDs(
        context: CanonicalSessionState.ContextTicket,
        topics: [Topic], preferences: ReaderPreferencesModel.Snapshot,
        adoptedGeneration: UUID?, adoptedLoadVersion: UUID?
    ) -> Set<String>? {
        guard preferences.userID == context.userID, preferences.loaded,
              !preferences.isLoading, !preferences.isSaving,
              preferences.generation == adoptedGeneration, let loadVersion = preferences.loadVersion,
              loadVersion == adoptedLoadVersion else { return nil }
        let ids = topicIDs(context: context, topics: topics)
        return ids.isEmpty ? nil : Set(ids)
    }
}
