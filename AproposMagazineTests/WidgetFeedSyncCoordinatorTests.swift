import XCTest
@testable import Apropos

/// Deliberately ignores cancellation so the generation guard, rather than a
/// cooperative network client, must prevent obsolete file/publication commits.
private actor ControlledWidgetImages {
    private var pending: [String: CheckedContinuation<WidgetFeedImageUpdate, Never>] = [:]
    private var observers: [String: CheckedContinuation<Void, Never>] = [:]

    func prepare(_ articles: [WidgetArticle]) async -> WidgetFeedImageUpdate {
        let name = articles.first?.name ?? ""
        return await withCheckedContinuation { continuation in
            pending[name] = continuation
            observers.removeValue(forKey: name)?.resume()
        }
    }

    func waitForRequest(_ name: String) async {
        if pending[name] != nil { return }
        await withCheckedContinuation { observers[name] = $0 }
    }

    func complete(_ name: String, update: WidgetFeedImageUpdate) {
        pending.removeValue(forKey: name)?.resume(returning: update)
    }
}

private actor ControlledWidgetPreparation {
    private var pending: [String: CheckedContinuation<[WidgetArticle], Error>] = [:]
    private var observers: [String: CheckedContinuation<Void, Never>] = [:]

    func prepare(_ source: WidgetFeedSource) async throws -> [WidgetArticle] {
        let name = source.entries.first?.widget.name ?? ""
        return try await withCheckedThrowingContinuation { continuation in
            pending[name] = continuation
            observers.removeValue(forKey: name)?.resume()
        }
    }

    func waitForRequest(_ name: String) async {
        if pending[name] != nil { return }
        await withCheckedContinuation { observers[name] = $0 }
    }

    func complete(_ source: WidgetFeedSource) {
        let name = source.entries.first?.widget.name ?? ""
        pending.removeValue(forKey: name)?.resume(returning: source.entries.map(\.widget))
    }
}

final class WidgetFeedSyncCoordinatorTests: XCTestCase {
    private func source(_ name: String) -> WidgetFeedSource {
        WidgetFeedSource(articles: [Article(
            id: "same-id", name: name, slug: "article", content: "", intro: "", topicID: "music",
            lastPublished: "2026-10-01T12:00:00Z"
        )], topics: [], articlesAreSorted: true)
    }

    @MainActor
    func testIdenticalPayloadIsPreparedAndSavedOnceWithNoUnchangedImageReload() async {
        var preparations = 0
        var saves = 0
        var imagePasses = 0
        var reloads = 0
        let coordinator = WidgetFeedSyncCoordinator(
            prepare: { source in preparations += 1; return source.entries.map(\.widget) },
            persist: { _ in saves += 1 },
            cacheImages: { _ in imagePasses += 1; return .unchanged },
            reloadImages: { reloads += 1 }, now: { Date(timeIntervalSince1970: 0) }
        )
        await coordinator.sync(source("a"))?.value
        XCTAssertNil(coordinator.sync(source("a")))
        XCTAssertEqual(preparations, 1)
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(imagePasses, 1)
        XCTAssertEqual(reloads, 0)
    }

    @MainActor
    func testRepeatedSyncWhileImagesArePendingJoinsOneOperation() async {
        let images = ControlledWidgetImages()
        var saves = 0
        var commits = 0
        var reloads = 0
        let coordinator = WidgetFeedSyncCoordinator(
            prepare: { $0.entries.map(\.widget) }, persist: { _ in saves += 1 },
            cacheImages: { await images.prepare($0) }, reloadImages: { reloads += 1 }
        )
        let first = coordinator.sync(source("a"))
        await images.waitForRequest("a")
        let repeated = coordinator.sync(source("a"))
        await images.complete("a", update: WidgetFeedImageUpdate { commits += 1; return ["same-id"] })
        await first?.value
        await repeated?.value
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(commits, 1)
        XCTAssertEqual(reloads, 1)
    }

    @MainActor
    func testMissingImagesRetryAfterCooldownWithoutResavingMetadata() async {
        var clock = Date(timeIntervalSince1970: 0)
        var preparations = 0
        var saves = 0
        var imagePasses = 0
        var reloads = 0
        let coordinator = WidgetFeedSyncCoordinator(
            prepare: { source in preparations += 1; return source.entries.map(\.widget) },
            persist: { _ in saves += 1 },
            cacheImages: { _ in
                imagePasses += 1
                return imagePasses == 1 ? .unchanged : WidgetFeedImageUpdate { ["same-id"] }
            },
            reloadImages: { reloads += 1 }, now: { clock }, imageRetryInterval: 30
        )
        await coordinator.sync(source("a"))?.value
        clock.addTimeInterval(29)
        XCTAssertNil(coordinator.sync(source("a")))
        clock.addTimeInterval(1)
        await coordinator.sync(source("a"))?.value
        XCTAssertEqual(preparations, 1)
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(imagePasses, 2)
        XCTAssertEqual(reloads, 1)
    }

    @MainActor
    func testOldImageCompletionCannotCommitFilesOrReloadAfterNewFeed() async {
        let images = ControlledWidgetImages()
        var savedNames: [String] = []
        var committedNames: [String] = []
        var reloads = 0
        let coordinator = WidgetFeedSyncCoordinator(
            prepare: { $0.entries.map(\.widget) },
            persist: { savedNames.append($0[0].name) },
            cacheImages: { await images.prepare($0) }, reloadImages: { reloads += 1 }
        )
        let old = coordinator.sync(source("old"))
        await images.waitForRequest("old")
        let new = coordinator.sync(source("new"))
        await images.waitForRequest("new")
        await images.complete("new", update: WidgetFeedImageUpdate { committedNames.append("new"); return ["same-id"] })
        await new?.value
        await images.complete("old", update: WidgetFeedImageUpdate { committedNames.append("old"); return ["same-id"] })
        await old?.value
        XCTAssertEqual(savedNames, ["old", "new"])
        XCTAssertEqual(committedNames, ["new"])
        XCTAssertEqual(reloads, 1)
    }

    @MainActor
    func testClearInvalidatesPendingImageCommitAndSamePayloadCanPublishAgain() async {
        let images = ControlledWidgetImages()
        var saves = 0
        var commits = 0
        let coordinator = WidgetFeedSyncCoordinator(
            prepare: { $0.entries.map(\.widget) }, persist: { _ in saves += 1 },
            cacheImages: { await images.prepare($0) }, reloadImages: {}
        )
        let old = coordinator.sync(source("a"))
        await images.waitForRequest("a")
        coordinator.invalidate()
        await images.complete("a", update: WidgetFeedImageUpdate { commits += 1; return ["same-id"] })
        await old?.value
        XCTAssertEqual(commits, 0)
        let fresh = coordinator.sync(source("a"))
        await images.waitForRequest("a")
        await images.complete("a", update: .unchanged)
        await fresh?.value
        XCTAssertEqual(saves, 2)
    }

    @MainActor
    func testNewSourceWithSamePayloadDoesNotResaveOrBypassImageCooldown() async {
        var preparations = 0
        var saves = 0
        var imagePasses = 0
        let coordinator = WidgetFeedSyncCoordinator(
            prepare: { source in preparations += 1; return Array(source.entries.prefix(5)).map(\.widget) },
            persist: { _ in saves += 1 }, cacheImages: { _ in imagePasses += 1; return .unchanged },
            reloadImages: {}, now: { Date(timeIntervalSince1970: 0) }
        )
        let first = source("a")
        await coordinator.sync(first)?.value
        // Switching to unsorted input changes preparation inputs, not output.
        let samePayload = WidgetFeedSource(articles: [Article(
            id: "same-id", name: "a", slug: "article", content: "", intro: "", topicID: "music",
            lastPublished: "2026-10-01T12:00:00Z"
        )], topics: [], articlesAreSorted: false)
        await coordinator.sync(samePayload)?.value
        XCTAssertEqual(preparations, 2)
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(imagePasses, 1)
    }

    @MainActor
    func testCanceledPreparationCannotOverwriteNewerPayload() async {
        let worker = ControlledWidgetPreparation()
        var savedNames: [String] = []
        let coordinator = WidgetFeedSyncCoordinator(
            prepare: { try await worker.prepare($0) },
            persist: { savedNames.append($0[0].name) }, cacheImages: { _ in .unchanged },
            reloadImages: {}
        )
        let oldSource = source("old")
        let newSource = source("new")
        let old = coordinator.sync(oldSource)
        await worker.waitForRequest("old")
        let new = coordinator.sync(newSource)
        await worker.waitForRequest("new")
        await worker.complete(newSource)
        await new?.value
        await worker.complete(oldSource)
        await old?.value
        XCTAssertEqual(savedNames, ["new"])
    }

    @MainActor
    func testPreparationFailureDoesNotPreventImmediateRetry() async {
        var attempts = 0
        var saves = 0
        let coordinator = WidgetFeedSyncCoordinator(
            prepare: { source in
                attempts += 1
                if attempts == 1 { throw CancellationError() }
                return source.entries.map(\.widget)
            },
            persist: { _ in saves += 1 }, cacheImages: { _ in .unchanged }, reloadImages: {}
        )
        await coordinator.sync(source("a"))?.value
        await coordinator.sync(source("a"))?.value
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(saves, 1)
    }
}
