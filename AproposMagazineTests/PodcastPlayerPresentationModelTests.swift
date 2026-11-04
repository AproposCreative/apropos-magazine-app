import Combine
import XCTest
@testable import Apropos

@MainActor
final class PodcastPlayerPresentationModelTests: XCTestCase {
    func testPlaybackRateTextPreservesEveryConfiguredQuarterStep() {
        let cases: [(Float, String)] = [(0.75, "0.75x"), (1, "1x"), (1.25, "1.25x"), (1.5, "1.5x"), (2, "2x")]
        for (value, expected) in cases {
            XCTAssertEqual(podcastPlaybackRateText(value), expected, "The rate label must describe the selected value")
        }
    }

    @MainActor private final class Memory {
        var value = PodcastPlayerPresentation.empty
        var queued: [@MainActor () -> Void] = []
        var reads = 0
        func flush() { let actions = queued; queued.removeAll(); actions.forEach { $0() } }
        func model() -> PodcastPlayerPresentationModel {
            .init(read: { self.reads += 1; return self.value }, schedule: { self.queued.append($0) })
        }
    }

    func testWillChangeReadsAfterAssignmentAndCoalescesTheActualEventBurst() {
        let memory = Memory(), events = PassthroughSubject<Void, Never>()
        let model = memory.model(); model.observe(events.eraseToAnyPublisher())
        events.send(); memory.value.activeEpisodeID = "episode-A"
        events.send(); memory.value.preparationID = UUID(); memory.value.preparationTitle = "Ny lyd"
        XCTAssertEqual(model.snapshot, .empty); XCTAssertEqual(memory.reads, 0)
        XCTAssertEqual(memory.queued.count, 1)
        memory.flush()
        XCTAssertEqual(model.snapshot, memory.value)
        XCTAssertEqual(model.snapshot.activeEpisodeID, "episode-A")
    }

    func testClockOnlyEventsDoNotPublishTheRootPresentation() {
        let memory = Memory(), model = memory.model()
        var publications = 0
        let subscription = model.objectWillChange.sink { publications += 1 }
        for _ in 0..<1000 { model.sourceWillChange(); memory.flush() }
        XCTAssertEqual(publications, 0); XCTAssertEqual(model.snapshot, .empty)
        memory.value.activeEpisodeID = "episode-A"; model.sourceWillChange(); memory.flush()
        XCTAssertEqual(publications, 1)
        for _ in 0..<100 { model.sourceWillChange(); memory.flush() }
        XCTAssertEqual(publications, 1)
        withExtendedLifetime(subscription) {}
    }

    func testPreparationPresentationAndErrorChangesArePreservedWithoutAClockField() {
        let memory = Memory(), model = memory.model(), id = UUID()
        memory.value.preparationID = id; memory.value.preparationTitle = "Verificerer gemt lyd"
        model.sourceWillChange(); memory.flush()
        XCTAssertEqual(model.snapshot.preparationID, id)
        memory.value.isFullPlayerPresented = true; model.sourceWillChange(); memory.flush()
        XCTAssertTrue(model.snapshot.isFullPlayerPresented)
        memory.value.preparationID = nil; memory.value.preparationTitle = nil
        memory.value.offlinePlaybackMessage = "Lyden kunne ikke bekræftes."
        model.sourceWillChange(); memory.flush()
        XCTAssertNil(model.snapshot.preparationID)
        XCTAssertEqual(model.snapshot.offlinePlaybackMessage, memory.value.offlinePlaybackMessage)
        memory.value.offlinePlaybackMessage = nil; memory.value.isFullPlayerPresented = false
        model.sourceWillChange(); memory.flush()
        XCTAssertEqual(model.snapshot, .empty)
    }

    func testReentrantSourceReplacementDoesNotCommitTheOlderPresentation() {
        let memory = Memory(), model = memory.model(); var once = true
        let subscription = model.objectWillChange.sink {
            if once {
                once = false; model.sourceWillChange(); memory.value.activeEpisodeID = "episode-B"
            }
        }
        memory.value.activeEpisodeID = "episode-A"; model.sourceWillChange(); memory.flush()
        XCTAssertNil(model.snapshot.activeEpisodeID)
        memory.flush(); XCTAssertEqual(model.snapshot.activeEpisodeID, "episode-B")
        withExtendedLifetime(subscription) {}
    }
}
