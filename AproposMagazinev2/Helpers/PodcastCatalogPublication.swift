import Combine
import Foundation

/// Post-state catalog observation for Home. The actor-owned provider is kept out
/// of this inert model, which also protects willChange reentry at publication.
@MainActor
final class PodcastCatalogPublication: ObservableObject {
    struct Snapshot: Equatable {
        let episodes: [PodcastEpisode]
        let revision: UUID
    }
    nonisolated let objectWillChange = ObservableObjectPublisher()
    private let subject = PassthroughSubject<Snapshot, Never>()
    private var operation = UUID()
    private var notifying = false
    private(set) var snapshot = Snapshot(episodes: [], revision: UUID())
    var changes: AnyPublisher<Snapshot, Never> {
        subject.filter { [weak self] in self?.snapshot.revision == $0.revision }.eraseToAnyPublisher()
    }
    func replace(_ episodes: [PodcastEpisode]) {
        let original = UUID()
        operation = original
        guard snapshot.episodes != episodes else { return }
        if !notifying { notifying = true; objectWillChange.send(); notifying = false }
        guard operation == original else { return }
        snapshot = Snapshot(episodes: episodes, revision: original)
        subject.send(snapshot)
    }
}
