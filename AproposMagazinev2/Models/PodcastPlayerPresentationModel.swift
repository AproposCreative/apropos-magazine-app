import Combine
import Foundation

/// The root and Home need presentation changes, never the playback clock.
/// Values are supplied by the production bridge or a local memory fixture.
struct PodcastPlayerPresentation: Equatable, Sendable {
    var activeEpisodeID: String?
    var preparationID: UUID?
    var preparationTitle: String?
    var isFullPlayerPresented: Bool
    var offlinePlaybackMessage: String?

    static let empty = PodcastPlayerPresentation(activeEpisodeID: nil, preparationID: nil,
        preparationTitle: nil, isFullPlayerPresented: false, offlinePlaybackMessage: nil)
    var hasActiveEpisode: Bool { activeEpisodeID != nil }
}

@MainActor
final class PodcastPlayerPresentationModel: ObservableObject {
    typealias Schedule = (@escaping @MainActor () -> Void) -> Void
    private(set) var snapshot: PodcastPlayerPresentation
    private let read: @MainActor () -> PodcastPlayerPresentation
    private let schedule: Schedule
    private var subscription: AnyCancellable?
    private var pending = false
    private var sourceRevision: UInt64 = 0

    init(initial: PodcastPlayerPresentation = .empty,
         read: @escaping @MainActor () -> PodcastPlayerPresentation,
         schedule: @escaping Schedule = { action in DispatchQueue.main.async { action() } }) {
        snapshot = initial
        self.read = read
        self.schedule = schedule
    }

    func observe(_ events: AnyPublisher<Void, Never>) {
        guard subscription == nil else { return }
        subscription = events.sink { [weak self] in self?.sourceWillChange() }
    }

    /// A player event can precede the property assignment. Coalesce reads until
    /// the next turn, then publish only a changed presentation tuple.
    func sourceWillChange() {
        sourceRevision &+= 1
        guard !pending else { return }
        pending = true
        schedule { [weak self] in
            guard let self else { return }
            self.pending = false
            self.synchronize()
        }
    }

    func synchronize() {
        let revision = sourceRevision
        let candidate = read()
        guard candidate != snapshot else { return }
        objectWillChange.send()
        // A notification can synchronously replace the source. Let its queued
        // post-turn read commit the newer value instead of publishing this one.
        guard revision == sourceRevision else { return }
        guard read() == candidate else { sourceWillChange(); return }
        snapshot = candidate
    }
}
