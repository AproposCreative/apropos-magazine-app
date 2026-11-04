#if DEBUG && targetEnvironment(simulator)
import Combine
import FirebaseCore
import SwiftUI
import UIKit

private struct LocalNotificationRoute: Hashable {
    let identifier: String
    let type: String
}

/// Real collection/recovery/journal admission with held memory completions.
/// The buttons drive only this local effect adapter, never product state fields.
@MainActor
private final class LocalFavoritesNoticeHarness: ObservableObject {
    @MainActor private final class Journal {
        let seed: FavoritesRecord
        var records: [FavoritesNamespace: FavoritesRecord] = [:]
        var held: [@MainActor (Bool) -> Void] = []
        var holdWrites = false
        var saveClock: TimeInterval = 0
        init(articles: [Article]) { seed = FavoritesRecord(articles: articles) }
        var storage: FavoritesModel.Storage {
            .init(read: { [weak self] namespace, complete in
                guard let self else { complete(.failure(FavoritesJournalFailure.readFailed)); return }
                if self.records[namespace] == nil { self.records[namespace] = self.seed }
                complete(.success(self.records[namespace]))
            }, write: { [weak self] namespace, record, expected, complete in
                guard let self else { complete(.failure(FavoritesJournalFailure.writeFailed)); return }
                let operation: @MainActor (Bool) -> Void = { [self] failing in
                    if failing { complete(.failure(FavoritesJournalFailure.writeFailed)); return }
                    guard self.records[namespace]?.recordRevision == expected else {
                        complete(.failure(FavoritesJournalFailure.staleRevision)); return
                    }
                    self.records[namespace] = record; complete(.success(()))
                }
                if self.holdWrites { self.held.append(operation) } else { operation(false) }
            })
        }
        func releaseAll(failing: Bool = false) {
            holdWrites = false
            let completions = held; held.removeAll()
            for complete in completions { complete(failing) }
        }
    }
    private struct VisibilityEvent {
        let visible: Bool
        let time: TimeInterval
        let state: String
        let generation: String
    }
    private struct PageEvent { let visible: Bool; let time: TimeInterval }
    let model: FavoritesModel
    let recentOrder: Bool
    let articles: [Article]
    @Published private(set) var ready = false
    @Published private(set) var phase = "preparing"
    private let journal: Journal
    private var observation: FavoritesModel.ObservationTicket?
    private var modelSubscription: AnyCancellable?
    private var work: Task<Void, Never>?
    private var started = false
    private var measuring = false
    private var previousState = FavoritesStorageState.unresolved
    private var pendingTransitions = 0
    private var metadataUpdates = 0
    private var shortCycles = 0
    private var retryGenerations: [String] = []
    private var originalGeneration = ""
    private var startTime: TimeInterval = 0
    private var failureTime: TimeInterval?
    private var pendingStartedTime: TimeInterval?
    private var membership: [FavoritesModel.MembershipTicket] = []
    private var latestRowY: CGFloat?
    private var rowYs: [CGFloat] = []
    private var pendingRowYs: [CGFloat] = []
    private var events: [VisibilityEvent] = []
    private var pendingEvents: [VisibilityEvent] = []
    private var noticeVisible = false
    private var pageVisible = false
    private var pageEvents: [PageEvent] = []
    private var pendingPageEvents: [PageEvent] = []
    private var fixtureIssue = ""

    init(articles: [Article], recentOrder: Bool = false) {
        self.recentOrder = recentOrder
        // Public journal records do not accept local file URLs. Use the same
        // metadata/IDs and enrich the visible rows from the local image fixture.
        self.articles = articles.map {
            Article(id: $0.id, name: $0.name ?? "", slug: $0.slug ?? $0.id, content: "", intro: "",
                stjerne: $0.stjerne, topicID: $0.topicID ?? "", contentRevision: $0.contentRevision)
        }
        let journal = Journal(articles: recentOrder ? [] : self.articles); self.journal = journal
        model = FavoritesModel(storage: journal.storage, now: {
            journal.saveClock += 100
            return Date(timeIntervalSince1970: journal.saveClock)
        })
        modelSubscription = model.changes.sink { [weak self] snapshot in
            guard let self, self.ready else { return }
            self.objectWillChange.send()
            if self.measuring, snapshot.state == .pending, self.previousState != .pending {
                self.pendingTransitions += 1
                if self.pendingStartedTime == nil { self.pendingStartedTime = Date.timeIntervalSinceReferenceDate }
            }
            self.previousState = snapshot.state
        }
    }
    func start() async {
        guard !started else { return }; started = true
        if recentOrder {
            model.changeContext(to: .guest)
            // Actual accepted save actions in a deliberate non-title/non-ID
            // order. These dates are injected test input, never legacy migration.
            for index in [1, 2, 0] where articles.indices.contains(index) {
                _ = model.setFavorite(articles[index], enabled: true)
            }
            ready = model.snapshot.articles.count == articles.count
            phase = ready ? "ready" : "failed"
            return
        }
        model.changeContext(to: .confirmed(userID: "local-notice-reader-A"))
        guard let ticket = model.recoveryTicket(), model.beginRecovery(ticket),
              await model.finishRecovery(ticket, success: true), let observation = model.observationTicket() else {
            fixtureIssue = "Lokal genoptagelse blev ikke klar"; phase = "failed"; return
        }
        self.observation = observation
        guard model.applyRemote(.init(articles: articles, isFromCache: false, hasPendingWrites: false), ticket: observation),
              model.snapshot.state == .ready else {
            fixtureIssue = "Lokal samling blev ikke klar"; phase = "failed"; return
        }
        membership = articles.compactMap { model.membershipTicket(articleID: $0.id) }
        previousState = model.snapshot.state
        events = []; pendingEvents = []; pendingTransitions = 0; rowYs = []; pendingRowYs = []
        phase = "ready"; ready = true
    }
    private func begin(_ next: String) -> Bool {
        guard ready, model.snapshot.state == .ready, observation != nil else { return false }
        work?.cancel(); measuring = true
        events = []; pendingEvents = []; rowYs = latestRowY.map { [$0] } ?? []; pendingRowYs = []
        pendingTransitions = 0; metadataUpdates = 0; shortCycles = 0; retryGenerations = []; failureTime = nil; pendingStartedTime = nil
        previousState = model.snapshot.state; originalGeneration = model.snapshot.generation.uuidString
        startTime = Date.timeIntervalSinceReferenceDate; phase = next
        pageEvents = [.init(visible: pageVisible, time: startTime)]; pendingPageEvents = []
        return true
    }
    @discardableResult private func remote(cache: Bool = false) -> Bool {
        guard let observation else { return false }
        let accepted = model.applyRemote(.init(articles: articles, isFromCache: cache, hasPendingWrites: false), ticket: observation)
        if accepted { metadataUpdates += 1 } else { fixtureIssue = "Lokal metadataobservation blev afvist" }
        return accepted
    }
    func runShortCycles() {
        guard begin("short-running") else { return }
        work = Task { @MainActor [weak self] in
            guard let self else { return }
            for delay in [80, 90, 100, 110] {
                guard !Task.isCancelled else { return }
                self.journal.holdWrites = true; _ = self.remote(cache: true)
                do { try await Task.sleep(for: .milliseconds(delay)) } catch { return }
                _ = self.remote()
                self.journal.releaseAll(); self.shortCycles += 1
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
            self.phase = "short-complete"
        }
    }
    func runSustained() {
        guard begin("sustained-waiting") else { return }
        work = Task { @MainActor [weak self] in
            guard let self else { return }
            // This local delivery latency lets the actual shared pager leave
            // the saved page before metadata arrives. It never controls the
            // product notice's delay, lifecycle or visibility state.
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard !Task.isCancelled else { return }
            self.journal.holdWrites = true; _ = self.remote(); self.phase = "sustained-running"
            for _ in 0..<30 {
                do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
                guard !Task.isCancelled else { return }
                _ = self.remote()
            }
            self.phase = "sustained-held"
        }
    }
    func runWriteFailure() {
        guard begin("failure-pending") else { return }
        journal.holdWrites = true; _ = remote()
        work = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.failureTime = Date.timeIntervalSinceReferenceDate
            self.journal.releaseAll(failing: true); self.phase = "write-failed"
        }
    }
    func changeOwnerDuringPending() {
        guard begin("owner-pending") else { return }
        journal.holdWrites = true; _ = remote()
        work = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.model.changeContext(to: .guest); self.observation = nil
            self.journal.releaseAll()
            self.phase = "owner-changed"
            do { try await Task.sleep(for: .milliseconds(850)) } catch { return }
            guard !Task.isCancelled else { return }; self.phase = "owner-complete"
        }
    }
    func resolve() {
        work?.cancel(); work = nil
        journal.releaseAll(); phase = "resolved"
    }
    func retry(_ generation: UUID) {
        guard model.snapshot.generation == generation else { return }
        retryGenerations.append(generation.uuidString)
        journal.holdWrites = true; model.retryStorage(); phase = "retry-held"
    }
    func cancelWork() { work?.cancel(); work = nil }
    func queueVisibility(_ visible: Bool) {
        guard measuring else { return }
        pendingEvents.append(.init(visible: visible, time: Date.timeIntervalSinceReferenceDate,
            state: String(describing: model.snapshot.state), generation: model.snapshot.generation.uuidString))
    }
    func queueRow(_ frame: CGRect) {
        latestRowY = frame.minY
        if measuring { pendingRowYs.append(frame.minY) }
    }
    func queuePageVisibility(_ visible: Bool) {
        pageVisible = visible
        guard measuring else { return }
        pendingPageEvents.append(.init(visible: visible, time: Date.timeIntervalSinceReferenceDate))
    }
    /// Called by the existing deferred fixture probe flush, including every
    /// lifecycle edge even if several arrive in the same SwiftUI update.
    func commitProbes() -> Bool {
        guard !pendingEvents.isEmpty || !pendingRowYs.isEmpty || !pendingPageEvents.isEmpty else { return false }
        events.append(contentsOf: pendingEvents); pendingEvents.removeAll()
        if let last = events.last { noticeVisible = last.visible }
        rowYs.append(contentsOf: pendingRowYs); pendingRowYs.removeAll()
        pageEvents.append(contentsOf: pendingPageEvents); pendingPageEvents.removeAll()
        return true
    }
    var report: [String: Any] {
        ["fixtureControlsReady": ready, "phase": phase,
         "modelState": String(describing: model.snapshot.state), "revision": model.snapshot.revision,
         "generation": model.snapshot.generation.uuidString, "originalGeneration": originalGeneration,
         "memberIDs": model.snapshot.articles.map(\.id).sorted(), "pendingIDs": model.snapshot.pendingArticleIDs.sorted(),
         "serverConfirmed": model.snapshot.serverConfirmed, "canRetry": model.snapshot.canRetry,
         "issueMessage": model.snapshot.issueMessage ?? "", "heldWrites": journal.held.count,
         "modelPendingTransitions": pendingTransitions, "metadataUpdates": metadataUpdates, "shortCycles": shortCycles,
         "noticeAppearances": events.filter(\.visible).count, "noticeVisible": noticeVisible,
         "visibilityEvents": events.map { event in ["visible": event.visible, "elapsed": event.time - startTime,
             "afterFailure": failureTime.map { event.time - $0 } ?? -1,
             "afterPending": pendingStartedTime.map { event.time - $0 } ?? -1,
             "state": event.state, "generation": event.generation] as [String: Any] },
         "pageVisible": pageVisible,
         "pageEvents": pageEvents.map { ["visible": $0.visible, "elapsed": $0.time - startTime] as [String: Any] },
         "firstRowYs": rowYs.map(Double.init), "retryGenerations": retryGenerations,
         "membershipTicketsCurrent": membership.count == articles.count && membership.allSatisfy(model.isCurrent),
         "fixtureIssue": fixtureIssue]
    }
}

/// Production pager, controls, saved rows and inbox; only data/routes are local.
@MainActor
private final class LocalNotificationInboxFixture: ObservableObject {
    private struct PagingReceipt: Equatable {
        let selectedPage: Int
        let dragTranslation: Double
        let progress: Double
        let viewportWidth: Double
        let reduceMotion: Bool
        let dragEnd: [String: Double]
        var json: [String: Any] { ["selectedPage": selectedPage, "dragTranslation": dragTranslation,
            "progress": progress, "viewportWidth": viewportWidth, "reduceMotion": reduceMotion, "dragEnd": dragEnd] }
    }
    final class Memory {
        var bytes: Data?
        var delivered: [NotificationInboxItem] = []
        var deliveredReads = 0
        var removed: [String] = []
        var badges = 0
        var badgeValues: [Int] = []
        var opened: [String] = []
        var openTypes: [String] = []
        var attempts: [String] = []
        var didOpen: ((NotificationInboxItem.Target) -> Void)?
        var displayURLs: [String: URL] = [:]
        var fixtureIssue = ""
    }
    @Published private(set) var model: NotificationInboxModel
    private let inboxEffects: NotificationInboxModel.Effects
    let metadata: ArticleViewModel
    let favoriteImages: OfflineArticleImageCache
    let favorites: [Article]
    let noticeHarness: LocalFavoritesNoticeHarness?
    @Published var path: [LocalNotificationRoute] = []
    @Published var selectedSort: FavoritesView.SortOption = .titleAZ {
        didSet {
            if controlsStabilityScenario || recentOrderScenario {
                sortDefaults.set(selectedSort.rawValue, forKey: FavoriteArticlesLogic.sortPreferenceKey)
            }
        }
    }
    private let sortDefaults = UserDefaults(suiteName: "apropos.local.favorite-sort-smoke")!
    let recentOrderScenario = ProcessInfo.processInfo.arguments.contains("-AproposFavoritesSavedOrderSmoke")
    @Published var selectedCategory = "Alle"
    @Published var showingSettings = false
    @Published private(set) var settingsRequests = 0
    @Published private(set) var searchRequests = 0
    @Published private(set) var removedFavoriteIDs: [String] = []
    let publicationCatchupScenario = ProcessInfo.processInfo.arguments.contains("-AproposNotificationPublicationCatchupSmoke")
    @Published var publicationLanguage: ArticleContentLanguage = ProcessInfo.processInfo.arguments.contains("-AproposNotificationPublicationEnglishSmoke") ? .english : .danish
    @Published private(set) var publicationLoads = 0
    @Published private(set) var publicationColdReloads = 0
    private var publicationArticles: [Article] = []
    private var publicationAcceptedSourceCount = 0
    private var publicationFirstBaselineCount: Int?
    private var newlyPublishedIDs: [String] = []
    private let publicationAvailability = ArticleAvailabilityModel(schedule: { _ in {} })
    let coverScenario = ProcessInfo.processInfo.arguments.contains("-AproposNotificationCoversSmoke")
    let reduceMotionOverride = ProcessInfo.processInfo.arguments.contains("-AproposMinSideReduceMotionSmoke")
    let controlsStabilityScenario = ProcessInfo.processInfo.arguments.contains("-AproposFavoritesControlsStabilitySmoke")
    @Published private(set) var controlsPhase = "startup"
    @Published private(set) var controlsRefreshes = 0
    private let memory: Memory
    private var frames: [String: CGRect] = [:]
    private var artworkPhases: [String: String] = [:]
    private var pendingFrames: [String: CGRect] = [:]
    private var pendingArtworkPhases: [String: String] = [:]
    private var probePublicationScheduled = false
    private var noticeSubscription: AnyCancellable?
    private var pagingSamples: [PagingReceipt] = []
    private var pendingPagingSamples: [PagingReceipt] = []
    private var layoutFrames: [String: CGRect] = [:]
    private var pendingLayoutFrames: [String: CGRect] = [:]
    private var candidateLayoutFrames: [String: [String: CGRect]] = [:]
    private var pendingCandidateLayoutFrames: [String: [String: CGRect]] = [:]
    private var rawLayoutEvents: [[String: Any]] = []
    private var pendingLayoutEvents: [[String: Any]] = []
    private var layoutSnapshots: [[String: Any]] = []
    private var rawLayoutSequence = 0
    private var rawLayoutDropped = 0
    private var layoutSnapshotDropped = 0
    private var controlsPageVisible = true
    private var controlsRefreshTask: Task<Void, Never>?
    private var activeControlCandidates: Set<String> = []

    init() {
        let memory = Memory(); self.memory = memory
        let covers = ProcessInfo.processInfo.arguments.contains("-AproposNotificationCoversSmoke")
        let reject = ProcessInfo.processInfo.arguments.contains("-AproposNotificationRejectRouteSmoke")
        let date = Date(timeIntervalSince1970: 1_793_369_000)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notification-pages-\(UUID().uuidString)", isDirectory: true)
        let warm = root.appendingPathComponent("warm.png"), cold = root.appendingPathComponent("cold.png")
        let cacheRoot = root.appendingPathComponent("favorite-images", isDirectory: true)
        var articles = [
            Article(id: "saved-culture", name: "Historien bag de store fortællinger", slug: "saved-culture", content: "",
                intro: "Kultur, mennesker og nye perspektiver.", topicID: "fixture-culture", mobileImageURL: warm, contentRevision: "notification-pages-r1"),
            Article(id: "saved-music", name: "Musikken samler os på tværs", slug: "saved-music", content: "",
                intro: "En gemt fortælling fra scenen.", stjerne: 5, topicID: "fixture-music", mobileImageURL: cold, contentRevision: "notification-pages-r1"),
            Article(id: "saved-film", name: "Et nyt blik på filmens verden", slug: "saved-film", content: "",
                intro: "Mød stemmerne bag billederne.", topicID: "fixture-culture", mobileImageURL: warm, contentRevision: "notification-pages-r1")
        ]
        if ProcessInfo.processInfo.arguments.contains("-AproposFavoritesControlsStabilitySmoke"), !recentOrderScenario {
            articles.append(Article(id: "saved-fourth", name: "Stemmer fra kulturlivet", slug: "saved-fourth", content: "",
                intro: "Endnu en gemt artikel i den lokale samling.", topicID: "fixture-culture", mobileImageURL: warm,
                contentRevision: "notification-pages-r1"))
        }
        favorites = articles
        noticeHarness = (ProcessInfo.processInfo.arguments.contains("-AproposFavoritesNoticeSmoke") || recentOrderScenario)
            ? LocalFavoritesNoticeHarness(articles: articles, recentOrder: recentOrderScenario) : nil
        let keys = Dictionary(uniqueKeysWithValues: articles.enumerated().map {
            ($0.element.id, String(repeating: String($0.offset + 1), count: 64))
        })
        let generation = UUID()
        favoriteImages = OfflineArticleImageCache(cacheDirectory: cacheRoot,
            download: { _ in throw URLError(.unsupportedURL) }, online: { false },
            preparationAccess: { id, revision in
                guard revision == "notification-pages-r1", let key = keys[id] else {
                    return .init(contentKey: nil, generation: generation, isCurrent: { false })
                }
                return .init(contentKey: key, generation: generation, isCurrent: { true })
            })
        metadata = ArticleViewModel(startup: ReaderSDKStartupState(), identity: CanonicalSessionState(), actualUserID: { nil })
        metadata.topics = [Topic(id: "fixture-culture", name: "Kultur"), Topic(id: "fixture-music", name: "Musik")]
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            guard let photo = UIImage(named: "FallbackImage")?.pngData() else { throw CocoaError(.fileReadUnknown) }
            try photo.write(to: warm)
            let image = UIGraphicsImageRenderer(size: CGSize(width: 140, height: 240)).image { context in
                UIColor(red: 0.06, green: 0.32, blue: 0.66, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 140, height: 240))
                UIColor.cyan.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 240))
                ("APROPOS" as NSString).draw(at: CGPoint(x: 15, y: 94), withAttributes: [
                    .font: UIFont.boldSystemFont(ofSize: 18), .foregroundColor: UIColor.white])
            }
            guard let bytes = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
            try bytes.write(to: cold)
            memory.displayURLs = ["https://covers.example.invalid/warm.png": warm,
                "https://covers.example.invalid/cold.png": cold,
                "https://covers.example.invalid/alternate.png": cold,
                "https://covers.example.invalid/missing.png": root.appendingPathComponent("does-not-exist.png")]
            for article in articles {
                guard let key = keys[article.id], let original = article.mobileImageURL else { continue }
                let directory = cacheRoot.appendingPathComponent(key, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let file = String(repeating: "a", count: 64) + ".png"
                try Data(contentsOf: original).write(to: directory.appendingPathComponent(file), options: .atomic)
                try JSONEncoder().encode([original.absoluteString: file])
                    .write(to: directory.appendingPathComponent("mapping.json"), options: .atomic)
            }
        } catch { memory.fixtureIssue = "Lokale prøvebilleder kunne ikke klargøres" }

        let genericBody = "En almindelig besked fra Apropos kan læses direkte her. "
            + "Du kan se hele beskeden, mens du ruller gennem listen. "
            + "Der er plads til mere end en kort forhåndsvisning, også når teksten er sat helt op. "
            + "Vi fortæller om redaktionen, nye oplevelser og det, der sker omkring magasinet. "
            + "Beskeden bliver på den samme side uden en detaljevisning eller en ekstra knap. "
            + "Der er ikke en ekstra side at åbne."
        var items = [
            NotificationInboxItem.make(id: "article-one", title: "Ny artikel fra Apropos Magazine",
                body: "En længere redaktionel besked om kultur, musik og de fortællinger, der samler os.", date: date,
                userInfo: covers ? ["type": "new_narration", "article_id": "fixture-article", "article_name": "Ny artikel fra Apropos Magazine", "thumbnail_url": "https://covers.example.invalid/warm.png"]
                    : ["type": "new_narration", "article_id": "fixture-article", "article_name": "Ny artikel fra Apropos Magazine"]),
            NotificationInboxItem.make(id: "audio-two", title: "En ny samtale er klar",
                body: "Lyt til den nye episode fra Apropos Magazine.", date: date.addingTimeInterval(-3600),
                userInfo: ["type": "new_podcast", "article_id": "fixture-audio"]),
            NotificationInboxItem.make(id: "narration-four", title: "En oplæst artikel er klar",
                body: "Lyt til den nye fortælling fra Apropos Magazine.", date: date.addingTimeInterval(-5400),
                userInfo: covers ? ["type": "new_narration", "article_id": "fixture-narration", "podcast_title": "En oplæst artikel fra Apropos", "cover_url": "https://covers.example.invalid/cold.png"]
                    : ["type": "new_narration", "article_id": "fixture-narration", "podcast_title": "En oplæst artikel fra Apropos"]),
            NotificationInboxItem.make(id: "manual-three", title: "En besked fra Apropos", body: genericBody,
                date: date.addingTimeInterval(-7200), userInfo: ["image": "https://covers.example.invalid/warm.png"])
        ].compactMap { $0 }
        if covers, let missing = NotificationInboxItem.make(id: "article-missing", title: "Artiklen uden et tilgængeligt cover",
            body: "Beskeden kan stadig læses, selvom billedfilen ikke kan indlæses.", date: date.addingTimeInterval(-10800),
            userInfo: ["type": "new_article", "article_id": "fixture-missing", "thumbnail_url": "https://covers.example.invalid/missing.png"]) {
            items.append(missing)
        }
        if publicationCatchupScenario {
            let sourceID = "0123456789abcdef01234567"
            publicationArticles = [
                Article(id: sourceID, name: "En ny artikel uden lyd eller push", slug: "publication-catchup", content: "Lokal dansk artikeltekst.",
                    intro: "Artiklen kommer fra en frisk lokal publiceringskilde.", topicID: "fixture-culture",
                    thumbURL: URL(string: "https://covers.example.invalid/warm.png"), isDraft: false, isArchived: false,
                    lastPublished: "2026-11-02T10:00:00.000Z", contentRevision: "cms-sha256-v1:" + String(repeating: "a", count: 64)),
                Article(id: "en_" + sourceID, name: "A new article without audio or push", slug: "publication-catchup", content: "Local English article body.",
                    intro: "The article comes from a fresh local publication source.", topicID: "fixture-culture",
                    thumbURL: URL(string: "https://covers.example.invalid/cold.png"), isDraft: false, isArchived: false,
                    lastPublished: "2026-11-02T10:01:00.000Z", contentRevision: "cms-sha256-v1:" + String(repeating: "b", count: 64),
                    contentLanguage: .english, sourceArticleID: sourceID, cmsLocaleId: ArticleContentLanguage.englishCMSLocaleID)
            ]
        }
        // Catchup begins with neither delivered pushes nor a pre-seeded inbox.
        memory.delivered = publicationCatchupScenario ? [] : items
        var effects = NotificationInboxModel.Effects(load: { memory.bytes }, save: { memory.bytes = $0 },
            delivered: { callback in memory.deliveredReads += 1; callback(memory.delivered) }, removeDelivered: { ids in
                memory.removed.append(contentsOf: ids); memory.delivered.removeAll { ids.contains($0.id) }
            }, clearBadge: { done in memory.badges += 1; done(true) }, open: { target in
                memory.attempts.append(target.identifier)
                guard !reject else { return false }
                memory.opened.append(target.identifier); memory.openTypes.append(target.type)
                memory.didOpen?(target); return true
            })
        effects.setBadge = { count, done in memory.badgeValues.append(count); done(true) }
        inboxEffects = effects
        model = NotificationInboxModel(effects: effects)
        memory.didOpen = { [weak self] target in
            self?.path.append(LocalNotificationRoute(identifier: target.identifier, type: target.type))
        }
        noticeSubscription = noticeHarness?.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        if controlsStabilityScenario || recentOrderScenario {
            if ProcessInfo.processInfo.arguments.contains("-ResetFavoritesSortPreferenceSmoke") {
                sortDefaults.removeObject(forKey: FavoriteArticlesLogic.sortPreferenceKey)
            }
            selectedSort = ProcessInfo.processInfo.arguments.contains("-AproposFavoritesSortTitleAZSmoke")
                ? .titleAZ : FavoriteArticlesLogic.sortPreference(rawValue: sortDefaults.string(forKey: FavoriteArticlesLogic.sortPreferenceKey))
        }
    }
    var filteredFavorites: [Article] {
        let visible = noticeHarness.map { harness in harness.model.snapshot.articles.map { entry in
            (favorites.first(where: { $0.id == entry.id }) ?? entry).withFavoriteSavedAt(entry.favoriteSavedAt)
        } } ?? favorites
        var values = visible.filter { !removedFavoriteIDs.contains($0.id) && (selectedCategory == "Alle" || topic(for: $0) == selectedCategory) }
        values = FavoriteArticlesLogic.sorted(values, by: selectedSort)
        return values
    }
    private func topic(for article: Article) -> String { metadata.topics.first { $0.id == article.topicID }?.name ?? "" }
    func showSettings() { settingsRequests += 1; showingSettings = true }
    func search() { searchRequests += 1 }
    func openFavorite(_ article: Article) { path.append(.init(identifier: article.id, type: "saved_article")) }
    func removeFavorites(at offsets: IndexSet) {
        let current = filteredFavorites
        for index in offsets where current.indices.contains(index) { removedFavoriteIDs.append(current[index].id) }
    }
    func displayURL(for remote: URL) -> URL? { memory.displayURLs[remote.absoluteString] }
    func recordFrame(_ key: String, _ frame: CGRect) {
        guard frame.origin.x.isFinite, frame.origin.y.isFinite, frame.width.isFinite, frame.height.isFinite,
              frame.width > 0, frame.height > 0,
              pendingFrames[key] != frame else { return }
        pendingFrames[key] = frame
        if key == "favorites.firstRow" { noticeHarness?.queueRow(frame) }
        if key == "favorites.firstRow" { recordControlFrame("firstRow", frame) }
        if key == "favorites.firstRow", controlsStabilityScenario { return }
        scheduleProbePublication()
    }
    func recordControlFrame(_ key: String, _ frame: CGRect) {
        recordControlsCandidateFrame("", key, frame)
    }
    func recordControlsCandidateFrame(_ candidate: String, _ key: String, _ frame: CGRect) {
        guard controlsStabilityScenario, frame.minX.isFinite, frame.minY.isFinite,
              frame.width.isFinite, frame.height.isFinite else { return }
        rawLayoutSequence += 1
        let page = pagingSamples.last(where: { $0.dragEnd.isEmpty })?.selectedPage ?? 0
        appendControlEvent(["sequence": rawLayoutSequence, "time": Date.timeIntervalSinceReferenceDate,
            "phase": controlsPhase, "signature": controlsSignature, "candidate": candidate, "key": key, "page": page,
            "pageVisible": controlsPageVisible, "activeCandidates": activeControlCandidates.sorted(), "frame": frameJSON(frame),
            "observation": "Raw geometry callback; candidate visibility is not inferred"])
        if frame.width > 0, frame.height > 0 {
            if candidate.isEmpty { pendingLayoutFrames[key] = frame }
            else { pendingCandidateLayoutFrames[candidate, default: [:]][key] = frame }
        }
        // History alone must not republish and cause a new measurement pass.
        // Explicit checkpoints and existing model/page publications flush it.
    }
    private func appendControlEvent(_ value: [String: Any]) {
        pendingLayoutEvents.append(value)
        if pendingLayoutEvents.count > 2048 {
            let count = pendingLayoutEvents.count - 2048; rawLayoutDropped += count; pendingLayoutEvents.removeFirst(count)
        }
    }
    func recordControlsCandidate(_ name: String, _ visible: Bool) {
        guard controlsStabilityScenario else { return }
        if visible { activeControlCandidates.insert(name) } else { activeControlCandidates.remove(name) }
        rawLayoutSequence += 1
        appendControlEvent(["sequence": rawLayoutSequence, "time": Date.timeIntervalSinceReferenceDate,
            "phase": controlsPhase, "signature": controlsSignature, "key": "candidate." + name,
            "visible": visible, "activeCandidates": activeControlCandidates.sorted(), "pageVisible": controlsPageVisible,
            "observation": "Actual candidate lifecycle; queued silently until checkpoint"])
    }
    func checkpointControls() { recordControlsMarker("explicit-checkpoint") }
    private func frameJSON(_ frame: CGRect) -> [String: Double] {
        ["x": Double(frame.minX), "y": Double(frame.minY), "width": Double(frame.width), "height": Double(frame.height)]
    }
    private func recordControlsMarker(_ name: String) {
        guard controlsStabilityScenario else { return }
        rawLayoutSequence += 1
        appendControlEvent(["sequence": rawLayoutSequence, "time": Date.timeIntervalSinceReferenceDate,
            "phase": controlsPhase, "signature": controlsSignature, "key": "marker." + name,
            "pageVisible": controlsPageVisible, "observation": "Fixture operation marker, not a geometry callback"])
        scheduleProbePublication()
    }
    private var controlsSignature: String {
        let width = (pendingFrames["minside.viewport"] ?? frames["minside.viewport"])?.width ?? 0
        return [selectedSort.rawValue, selectedCategory, String(filteredFavorites.count),
            UIApplication.shared.preferredContentSizeCategory.rawValue, String(format: "%.3f", Double(width))].joined(separator: "|")
    }
    private var selectedControlFrames: [String: CGRect] {
        guard activeControlCandidates.count == 1, let candidate = activeControlCandidates.first else { return layoutFrames }
        return layoutFrames.merging(candidateLayoutFrames[candidate] ?? [:]) { _, selected in selected }
    }
    private func controlSnapshot() -> [String: Any]? {
        let required = ["container", "sort", "category", "search", "count", "firstRow"]
        let values = selectedControlFrames
        guard required.allSatisfy({ values[$0] != nil }), let container = values["container"],
              let first = values["firstRow"] else { return nil }
        let coherent = ["sort", "category", "search", "count"].allSatisfy {
            guard let value = values[$0] else { return false }
            return container.insetBy(dx: -1, dy: -1).contains(value)
        } && first.minY >= container.maxY - 1
        let width = (pendingFrames["minside.viewport"] ?? frames["minside.viewport"])?.width ?? 0
        return ["phase": controlsPhase, "signature": controlsSignature, "pageVisible": controlsPageVisible,
            "viewportWidth": Double(width), "coherent": coherent,
            "activeCandidates": activeControlCandidates.sorted(), "candidateQualified": activeControlCandidates.count == 1,
            "frames": Dictionary(uniqueKeysWithValues: required.compactMap { key in values[key].map { (key, frameJSON($0)) } }),
            "observation": "Coherent geometry only; native screen/video determines visible rendering"]
    }
    func advanceControlsPhase() {
        let phases = ["startup", "sort-menu", "category-menu", "header-roundtrip", "refresh"]
        if let index = phases.firstIndex(of: controlsPhase), index + 1 < phases.count { controlsPhase = phases[index + 1] }
        recordControlsMarker("phase")
    }
    func refreshUnchangedControlsInputs() {
        guard controlsStabilityScenario else { return }
        controlsRefreshTask?.cancel(); controlsRefreshes = 0
        controlsRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<4 {
                guard !Task.isCancelled else { return }
                // The existing injected model publishes its real refresh states;
                // delivered IDs and saved-list inputs remain unchanged.
                self.model.refresh(); self.controlsRefreshes += 1; self.recordControlsMarker("real-model-refresh")
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
            self.controlsPhase = "refresh-complete"
            self.recordControlsMarker("refresh-complete")
        }
    }
    func recordNoticeVisibility(_ visible: Bool) {
        noticeHarness?.queueVisibility(visible)
        scheduleProbePublication()
    }
    func recordNoticeFrame(_ frame: CGRect) { recordFrame("favorites.notice", frame) }
    func recordNoticePageVisibility(_ visible: Bool) {
        controlsPageVisible = visible
        recordControlsMarker(visible ? "saved-visible" : "saved-hidden")
        noticeHarness?.queuePageVisibility(visible); scheduleProbePublication()
    }
    func recordMinSidePaging(_ sample: MinSidePagingSample) {
        guard sample.dragTranslation.isFinite, sample.progress.isFinite,
              sample.viewportWidth.isFinite, sample.viewportWidth > 0 else { return }
        let value = PagingReceipt(selectedPage: sample.selectedPage, dragTranslation: sample.dragTranslation,
            progress: sample.progress, viewportWidth: sample.viewportWidth, reduceMotion: sample.reduceMotion,
            dragEnd: sample.dragEnd)
        guard (pendingPagingSamples.last ?? pagingSamples.last) != value else { return }
        pendingPagingSamples.append(value); scheduleProbePublication()
    }
    func recordArtwork(_ key: String, _ phase: String) {
        guard pendingArtworkPhases[key] != phase else { return }
        pendingArtworkPhases[key] = phase
        scheduleProbePublication()
    }
    private func scheduleProbePublication() {
        guard !probePublicationScheduled else { return }
        probePublicationScheduled = true
        // Loader cache callbacks can occur during a SwiftUI body update. Only
        // this read-only fixture observation is deferred, never product actions.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let nextFrames = self.frames.merging(self.pendingFrames) { _, latest in latest }
            let nextPhases = self.artworkPhases.merging(self.pendingArtworkPhases) { _, latest in latest }
            let noticeChanged = self.noticeHarness?.commitProbes() ?? false
            let pagingChanged = !self.pendingPagingSamples.isEmpty
            if pagingChanged {
                self.pagingSamples.append(contentsOf: self.pendingPagingSamples)
                self.pendingPagingSamples.removeAll()
                if self.pagingSamples.count > 256 { self.pagingSamples.removeFirst(self.pagingSamples.count - 256) }
            }
            let layoutChanged = !self.pendingLayoutEvents.isEmpty
            if layoutChanged {
                self.rawLayoutEvents.append(contentsOf: self.pendingLayoutEvents); self.pendingLayoutEvents.removeAll()
                self.layoutFrames.merge(self.pendingLayoutFrames) { _, latest in latest }; self.pendingLayoutFrames.removeAll()
                for (candidate, values) in self.pendingCandidateLayoutFrames {
                    self.candidateLayoutFrames[candidate, default: [:]].merge(values) { _, latest in latest }
                }
                self.pendingCandidateLayoutFrames.removeAll()
                if self.rawLayoutEvents.count > 2048 {
                    let count = self.rawLayoutEvents.count - 2048; self.rawLayoutDropped += count; self.rawLayoutEvents.removeFirst(count)
                }
            }
            if self.controlsStabilityScenario, layoutChanged || pagingChanged, let snapshot = self.controlSnapshot() {
                self.layoutSnapshots.append(snapshot)
                if self.layoutSnapshots.count > 512 { self.layoutSnapshotDropped += 1; self.layoutSnapshots.removeFirst() }
            }
            self.pendingFrames.removeAll(); self.pendingArtworkPhases.removeAll()
            self.probePublicationScheduled = false
            guard nextFrames != self.frames || nextPhases != self.artworkPhases || noticeChanged || pagingChanged || layoutChanged else { return }
            self.objectWillChange.send()
            self.frames = nextFrames; self.artworkPhases = nextPhases
        }
    }
    func refreshPublishedArticles() {
        guard publicationCatchupScenario else { return }
        // Same fresh-source admission and actual inbox ingestion as production;
        // no receive(), synthetic notification payload or audio service is used.
        let sources = ArticleContentLanguage.allCases.map { language in
            ArticleMirrorCatalog.Source(language: language, documents: publicationArticles.filter {
                $0.contentLanguage == language
            }.map { article in
                var data: [String: Any] = ["id": article.id, "contentLanguage": language.rawValue,
                    "isDraft": false, "isArchived": false]
                if let source = article.sourceArticleID { data["sourceArticleID"] = source }
                if let locale = article.cmsLocaleId { data["cmsLocaleId"] = locale }
                return (id: article.id, data: data)
            }, isFromCache: false, hasPendingWrites: false)
        }
        let confirmed = ArticleMirrorCatalog.confirmedPublications(from: publicationArticles, sources: sources)
        publicationAcceptedSourceCount = confirmed.count
        let ticket = publicationAvailability.beginRead()
        publicationAvailability.recordPublications(confirmed, ticket: ticket)
        model.synchronizeBadge(language: publicationLanguage)
        model.reconcilePublishedArticles(confirmed, verifiedLanguages: Set(sources.map(\.language)), stillCurrent: { true },
            permitsArticle: publicationAvailability.permitsBody)
        if publicationLoads == 0 { publicationFirstBaselineCount = model.items.count }
        model.refresh()
        publicationLoads += 1
    }
    func publishNewArticle() {
        guard publicationCatchupScenario, publicationLoads > 0 else { return }
        let sourceID = "89abcdef0123456789abcdef"
        guard let identifier = publicationLanguage.articleID(sourceID: sourceID) else {
            memory.fixtureIssue = "Den lokale publiceringsidentitet var ugyldig"
            return
        }
        if !publicationArticles.contains(where: { $0.id == identifier }) {
            let english = publicationLanguage == .english
            publicationArticles.append(Article(id: identifier,
                name: english ? "A genuinely new article without audio or push" : "En helt ny artikel uden lyd eller push",
                slug: "new-publication-after-baseline", content: english ? "New local English body." : "Ny lokal dansk artikeltekst.",
                intro: english ? "Published after the initial catalog." : "Udgivet efter det første katalog.", topicID: "fixture-culture",
                thumbURL: URL(string: english ? "https://covers.example.invalid/cold.png" : "https://covers.example.invalid/warm.png"),
                isDraft: false, isArchived: false, lastPublished: "2026-11-02T10:02:00.000Z",
                contentRevision: "cms-sha256-v1:" + String(repeating: english ? "d" : "c", count: 64),
                contentLanguage: publicationLanguage, sourceArticleID: english ? sourceID : nil,
                cmsLocaleId: english ? ArticleContentLanguage.englishCMSLocaleID : nil))
            newlyPublishedIDs.append(identifier)
        }
        // This changes the fake source inventory, then follows the SAME fresh
        // source/availability/ingest path. It never calls receive() or emits push.
        refreshPublishedArticles()
    }
    func changePublicationLanguage() {
        publicationLanguage = publicationLanguage == .danish ? .english : .danish
        model.synchronizeBadge(language: publicationLanguage)
    }
    func coldReloadPublishedInbox() {
        guard publicationCatchupScenario else { return }
        model = NotificationInboxModel(effects: inboxEffects)
        model.synchronizeBadge(language: publicationLanguage)
        publicationColdReloads += 1
    }
    private var publicationReport: [String: Any] {
        ["enabled": publicationCatchupScenario, "deliveredPushCount": memory.delivered.count,
         "freshPublicationLoads": publicationLoads, "coldModelReloads": publicationColdReloads,
         "confirmedFreshSourceCount": publicationAcceptedSourceCount,
         "firstBaselineItemCount": publicationFirstBaselineCount ?? -1,
         "newlyPublishedIDs": newlyPublishedIDs,
         "unreadCount": model.visibleItems(language: publicationLanguage).filter { !$0.isRead }.count,
         "recordedBadgeValue": memory.badgeValues.last ?? -1,
         "recordedBadgeValues": memory.badgeValues,
         "badgeEffectIsLocalSpyNotOSBadge": true,
         "selectedLanguage": publicationLanguage.rawValue, "itemIDs": model.items.map(\.id),
         "visibleDanishIDs": model.visibleItems(language: .danish).map(\.id),
         "visibleEnglishIDs": model.visibleItems(language: .english).map(\.id),
         "publicationSourceIDs": publicationArticles.map(\.id),
         "audioServiceOrRepositoryInjected": false,
         "freshSourceStillPermitted": publicationArticles.allSatisfy(publicationAvailability.permitsBody)]
    }
    func changeArticleCover() {
        guard let old = memory.delivered.first, old.id == "article-one" else { return }
        let updated = NotificationInboxItem(id: old.id, title: old.title, body: old.body, date: old.date,
            target: old.target, isRead: old.isRead, articleImageURL: URL(string: "https://covers.example.invalid/alternate.png"))
        memory.delivered[0] = updated; model.receive(updated)
    }
    var report: String {
        let value: [String: Any] = ["firebaseStarted": FirebaseApp.allApps != nil,
            "publicationCatchup": publicationReport,
            "count": model.items.count, "badgeClears": memory.badges, "deliveredReads": memory.deliveredReads,
            "localUnreadCount": model.visibleItems(language: publicationLanguage).filter { !$0.isRead }.count,
            "qualifiedUnreadCount": model.badgeInput.received.filter { $0.languageCode == nil || $0.languageCode == publicationLanguage.rawValue }.count,
            "recordedBadgeValue": memory.badgeValues.last ?? -1, "badgeEffectIsLocalSpyNotOSBadge": true,
            "removed": memory.removed,
            "opened": memory.opened, "openTypes": memory.openTypes, "attempts": memory.attempts,
            "path": path.map { ["identifier": $0.identifier, "type": $0.type] },
            "selectedSort": selectedSort.rawValue, "selectedSortTitle": selectedSort.titleKey,
            "storedSortPreference": sortDefaults.string(forKey: FavoriteArticlesLogic.sortPreferenceKey) ?? "",
            "savedAtByID": Dictionary(uniqueKeysWithValues: (noticeHarness?.model.snapshot.articles ?? favorites).compactMap { article in
                article.favoriteSavedAt.map { (article.id, $0) }
            }), "selectedCategory": selectedCategory,
            "favoriteIDs": filteredFavorites.map(\.id), "removedFavoriteIDs": removedFavoriteIDs,
            "settingsRequests": settingsRequests, "searchRequests": searchRequests,
            "systemAccessibility": UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory,
            "systemTextCategory": UIApplication.shared.preferredContentSizeCategory.rawValue,
            "systemReduceMotion": UIAccessibility.isReduceMotionEnabled, "reduceMotionOverride": reduceMotionOverride,
            "pagingSamples": pagingSamples.map(\.json),
            "paging": pagingSamples.last(where: { $0.dragEnd.isEmpty })?.json ?? [:],
            "bodyLineHeight": UIFont.preferredFont(forTextStyle: .subheadline).lineHeight,
            "fixtureIssue": memory.fixtureIssue, "favoritesFixture": "Actual controls and rows; local metadata, cache and callbacks only",
            "notice": noticeHarness?.report ?? [:],
            "controlsStability": ["enabled": controlsStabilityScenario, "phase": controlsPhase,
                "refreshes": controlsRefreshes, "signature": controlsSignature,
                "rawEvents": rawLayoutEvents, "snapshots": layoutSnapshots,
                "rawDropped": rawLayoutDropped, "snapshotsDropped": layoutSnapshotDropped,
                "activeCandidates": activeControlCandidates.sorted(),
                "layoutFrames": selectedControlFrames.mapValues(frameJSON),
                "candidateFrames": candidateLayoutFrames.mapValues { $0.mapValues(frameJSON) }],
            "artworkPhases": artworkPhases,
            "imageURLs": Dictionary(uniqueKeysWithValues: model.items.compactMap { item in
                item.articleImageURL.map { (item.id, $0.absoluteString) }
            }),
            "frames": frames.mapValues { ["x": $0.minX, "y": $0.minY, "width": $0.width, "height": $0.height] }]
        let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}

@MainActor
struct LocalNotificationInboxSmokeView: View {
    @StateObject private var fixture = LocalNotificationInboxFixture()
    var body: some View {
        if fixture.publicationCatchupScenario {
            LocalNotificationInboxContent(fixture: fixture, model: fixture.model)
                .environment(\.locale, AppLocalization.locale(for: fixture.publicationLanguage))
        } else {
            LocalNotificationInboxContent(fixture: fixture, model: fixture.model)
        }
    }
}
@MainActor
private struct LocalNotificationInboxContent: View {
    @ObservedObject var fixture: LocalNotificationInboxFixture
    @ObservedObject var model: NotificationInboxModel
    var body: some View {
        NavigationStack(path: $fixture.path) {
            MinSidePages(model: model, coverDisplayURL: fixture.displayURL, onSettings: fixture.showSettings) {
                savedList
            }
            .environment(\.notificationInboxGeometryProbe, fixture.recordFrame)
            .environment(\.notificationInboxArtworkProbe, fixture.recordArtwork)
            .environment(\.minSidePagingProbe, fixture.recordMinSidePaging)
            .environment(\.minSideReduceMotionOverride, fixture.reduceMotionOverride)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: LocalNotificationRoute.self) { route in
                LocalNotificationRouteReceipt(route: route)
            }
        }
        .task { await fixture.noticeHarness?.start() }
        .onDisappear { fixture.noticeHarness?.cancelWork() }
        .safeAreaInset(edge: .bottom) {
            if fixture.publicationCatchupScenario {
                HStack {
                    Button("Opfrisk", action: fixture.refreshPublishedArticles)
                        .accessibilityIdentifier("notifications.fixture.publication.refresh")
                    Button("Udgiv", action: fixture.publishNewArticle)
                        .accessibilityIdentifier("notifications.fixture.publication.publish")
                    Button("Genåbn", action: fixture.coldReloadPublishedInbox)
                        .accessibilityIdentifier("notifications.fixture.publication.coldReload")
                    Button(fixture.publicationLanguage == .danish ? "English" : "Dansk", action: fixture.changePublicationLanguage)
                        .accessibilityIdentifier("notifications.fixture.publication.language")
                }.font(.caption).dynamicTypeSize(.large).buttonStyle(.bordered).padding(4)
            }
            if let notice = fixture.noticeHarness, !notice.recentOrder { LocalFavoritesNoticeControls(harness: notice) }
            if fixture.controlsStabilityScenario {
                HStack {
                    Button("Mål", action: fixture.checkpointControls)
                        .accessibilityIdentifier("favorites.controls.fixture.checkpoint")
                    Button("Næste fase", action: fixture.advanceControlsPhase)
                        .accessibilityIdentifier("favorites.controls.fixture.phase")
                    Button("Opfrisk", action: fixture.refreshUnchangedControlsInputs)
                        .accessibilityIdentifier("favorites.controls.fixture.refresh")
                }.font(.caption).dynamicTypeSize(.large).buttonStyle(.bordered).padding(4)
            }
        }
        .sheet(isPresented: $fixture.showingSettings) {
            VStack(spacing: 20) {
                Text("Indstillinger").font(.title).accessibilityIdentifier("notifications.fixture.settings")
                Text("Lokal kvittering for den delte knap. Ingen kontoservice er startet.")
                Button("Luk") { fixture.showingSettings = false }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("notifications.fixture.settings.close")
            }.padding(24)
        }
        .overlay(alignment: .bottomLeading) {
            VStack(spacing: 0) {
                Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase er startet")
                    .accessibilityIdentifier("notifications.fixture.firebase")
                Text(fixture.report).accessibilityIdentifier("notifications.fixture.report")
            }
            .font(.system(size: 1)).lineLimit(1).frame(height: 2).allowsHitTesting(false)
        }
    }
    @ViewBuilder private var savedList: some View {
        if let notice = fixture.noticeHarness {
            savedListContent.deferBriefFavoritesFeedback(model: notice.model)
        } else {
            savedListContent
        }
    }
    private var savedListContent: some View {
        List {
            Section {
                FavoritesControls(selectedSort: $fixture.selectedSort, selectedCategory: $fixture.selectedCategory,
                    availableCategories: ["Kultur", "Musik"], articleCount: fixture.filteredFavorites.count,
                    onSearch: fixture.search)
                    .environment(\.favoritesControlsCandidateProbe, fixture.recordControlsCandidate)
                    .environment(\.favoritesControlsCandidateFrameProbe, fixture.recordControlsCandidateFrame)
            }
            .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Color.clear)
            if let notice = fixture.noticeHarness, notice.ready {
                Section {
                    FavoritesNotice(model: notice.model, deferPendingFeedback: true, retry: notice.retry)
                        .environment(\.favoritesNoticeVisibilityProbe, fixture.recordNoticeVisibility)
                        .environment(\.favoritesNoticeFrameProbe, fixture.recordNoticeFrame)
                }
                .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
            Section {
                ForEach(fixture.filteredFavorites) { article in
                    Button { fixture.openFavorite(article) } label: {
                        FavoriteArticleRow(article: article, fixtureImageCache: fixture.favoriteImages,
                            onFrame: { key, frame in
                                if article.id == fixture.filteredFavorites.first?.id, key == "content" {
                                    fixture.recordFrame("favorites.firstRow", frame)
                                }
                            })
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("notifications.fixture.favorite.\(article.id)")
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .onDelete(perform: fixture.removeFavorites)
            }
            if fixture.coverScenario {
                Section {
                    Button("Skift artikelcover", action: fixture.changeArticleCover)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("notifications.fixture.changeCover")
                }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
        .accessibilityIdentifier("notifications.fixture.favorites")
        .environmentObject(fixture.metadata)
        .modifier(LocalSavedPageVisibilityProbe(onChange: fixture.recordNoticePageVisibility))
    }
}

/// Read the real shared container's selected-page environment. Stable page
/// hosts do not disappear when offset off screen, so lifecycle alone is not a
/// visibility receipt. This observation never writes the container's state.
private struct LocalSavedPageVisibilityProbe: ViewModifier {
    @Environment(\.minSidePageIsVisible) private var visible
    let onChange: (Bool) -> Void
    func body(content: Content) -> some View {
        content.onAppear { onChange(visible) }
            .onChange(of: visible) { _, new in onChange(new) }
            .onDisappear { onChange(false) }
    }
}

@MainActor
private struct LocalFavoritesNoticeControls: View {
    @ObservedObject var harness: LocalFavoritesNoticeHarness
    var body: some View {
        VStack(spacing: 2) {
            Text(harness.ready ? "Lokale kontroller klar" : "Klargør lokal samling")
                .accessibilityIdentifier("favorites.notice.fixture.ready")
            HStack(spacing: 4) {
                Button("Kort", action: harness.runShortCycles).accessibilityIdentifier("favorites.notice.fixture.short")
                Button("Lang", action: harness.runSustained).accessibilityIdentifier("favorites.notice.fixture.sustained")
                Button("Aflevér", action: harness.resolve).accessibilityIdentifier("favorites.notice.fixture.resolve")
                Button("Fejl", action: harness.runWriteFailure).accessibilityIdentifier("favorites.notice.fixture.failure")
                Button("Skift", action: harness.changeOwnerDuringPending).accessibilityIdentifier("favorites.notice.fixture.owner")
            }
            .buttonStyle(.bordered).frame(minHeight: 44).disabled(!harness.ready)
        }
        .font(.caption).dynamicTypeSize(.large).padding(4).background(.regularMaterial)
    }
}

private struct LocalNotificationRouteReceipt: View {
    let route: LocalNotificationRoute
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 16) {
            Text(route.identifier).font(.title2).accessibilityIdentifier("notifications.fixture.destination")
            Text(route.type).accessibilityIdentifier("notifications.fixture.destination.type")
            Text("Den rigtige meddelelsesrække har kaldt sin typede rute. Dette er en lokal navigationskvittering, ikke hentning eller afspilning.")
            Button("Tilbage til Min side") { dismiss() }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("notifications.fixture.route.back")
        }
        .padding(24).navigationTitle("Lokal indholdsrute").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
#endif
