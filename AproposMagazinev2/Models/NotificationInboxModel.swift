import Combine
import CryptoKit
import Foundation

/// Device-local notification presentation. Only recognized editorial payloads
/// are retained; unclassified/test notification text stays in memory.
struct NotificationInboxItem: Codable, Equatable, Identifiable, Sendable {
    enum Origin: String, Codable, Sendable { case received, publication }
    struct Target: Codable, Equatable, Sendable {
        let identifier: String
        let slug: String?
        let type: String
        let podcastTitle: String?

        private enum CodingKeys: String, CodingKey { case identifier, slug, type, podcastTitle }
        init(identifier: String, slug: String?, type: String, podcastTitle: String? = nil) {
            self.identifier = identifier; self.slug = slug
            let title = Self.validatedPodcastTitle(podcastTitle)
            let admittedTitle = ["new_podcast", "new_narration"].contains(type) ? title : nil
            self.podcastTitle = admittedTitle
            // Article-outbox messages also use new_narration when audio became
            // available. Only retained explicit podcast metadata makes that an
            // audio tap here; legacy inbox targets lost it, so open the article.
            self.type = type == "new_narration" && admittedTitle == nil ? "new_article" : type
        }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let title = try? values.decode(String.self, forKey: .podcastTitle)
            self.init(identifier: try values.decode(String.self, forKey: .identifier),
                      slug: try values.decodeIfPresent(String.self, forKey: .slug),
                      type: try values.decode(String.self, forKey: .type), podcastTitle: title)
        }
        var payload: NotificationNavigation.Payload {
            .init(articleIdentifier: identifier, articleSlug: slug, type: type, podcastTitle: podcastTitle)
        }
        private static func validatedPodcastTitle(_ raw: String?) -> String? {
            guard let raw, raw.utf8.count <= 1_000 else { return nil }
            let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return !title.isEmpty && title.count <= 240 ? title : nil
        }
    }
    let id: String
    let title: String
    let body: String
    let date: Date
    let target: Target?
    let articleImageURL: URL?
    var isRead: Bool = false
    var origin: Origin?

    private enum CodingKeys: String, CodingKey {
        case id, title, body, date, target, articleImageURL, isRead, origin
    }
    init(id: String, title: String, body: String, date: Date, target: Target?,
          isRead: Bool = false, articleImageURL: URL? = nil, origin: Origin? = nil) {
        self.id = id; self.title = title; self.body = body; self.date = date
        self.target = target; self.isRead = isRead
        self.origin = origin
        self.articleImageURL = Self.validatedArticleImageURL(articleImageURL?.absoluteString, target: target)
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        body = try values.decode(String.self, forKey: .body)
        date = try values.decode(Date.self, forKey: .date)
        target = try values.decodeIfPresent(Target.self, forKey: .target)
        isRead = try values.decode(Bool.self, forKey: .isRead)
        origin = try values.decodeIfPresent(Origin.self, forKey: .origin)
        // Version 1 records from 135 have no artwork field. Malformed optional
        // artwork becomes text-only without discarding a valid message/history.
        let rawImage = try? values.decode(String.self, forKey: .articleImageURL)
        articleImageURL = Self.validatedArticleImageURL(rawImage, target: target)
    }

    var canPersist: Bool {
        guard let target, target.payload.isArticleNotification || target.payload.isPodcastNotification else { return false }
        return !id.isEmpty && id.utf8.count <= 512 && !title.isEmpty && title.count <= 240 && title.utf8.count <= 1_000
            && body.count <= 1600 && body.utf8.count <= 6_500
            && date.timeIntervalSince1970.isFinite && !target.identifier.isEmpty
            && target.identifier.utf8.count <= 256 && (target.slug.map { $0.utf8.count <= 256 } ?? true)
            && (target.podcastTitle.map { !$0.isEmpty && $0.count <= 240 && $0.utf8.count <= 1_000 } ?? true)
            && (articleImageURL.map { Self.validatedArticleImageURL($0.absoluteString, target: target) != nil } ?? true)
    }

    static func make(id: String, title: String, body: String, date: Date,
                     userInfo: [AnyHashable: Any]) -> Self? {
        guard !id.isEmpty, id.utf8.count <= 512, date.timeIntervalSince1970.isFinite else { return nil }
        // Bound bytes before traversing graphemes: a single combining sequence
        // can contain arbitrarily many scalars despite having character count1.
        let title = String(String(decoding: title.utf8.prefix(960), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        let body = String(String(decoding: body.utf8.prefix(6_400), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines).prefix(1600))
        guard !title.isEmpty || !body.isEmpty else { return nil }
        let payload = NotificationNavigation.payload(from: userInfo)
        let normalized = NotificationNavigation.normalize(userInfo)
        let hasOwner = ["uid", "user_id", "userId", "owner_uid"].contains { normalized[$0] != nil }
        let recognized = payload.map { $0.isArticleNotification || $0.isPodcastNotification } ?? false
        let target: Target? = !hasOwner && recognized ? payload.flatMap { p in
            guard p.articleIdentifier.utf8.count <= 256,
                  p.articleSlug.map({ $0.utf8.count <= 256 }) ?? true else { return nil }
            return Target(identifier: p.articleIdentifier, slug: p.articleSlug, type: p.type, podcastTitle: p.podcastTitle)
        } : nil
        let imageKeys = ["thumbnail_url", "cover_url", "image"]
        var imageCandidates = imageKeys.compactMap { normalized[$0] as? String }
        if let options = normalized["fcm_options"] as? [String: Any], let image = options["image"] as? String {
            imageCandidates.append(image)
        }
        let articleImageURL = imageCandidates.lazy.compactMap {
            validatedArticleImageURL($0, target: target)
        }.first
        return .init(id: id, title: title.isEmpty ? "Apropos Magazine" : title,
                     body: body, date: date, target: target, articleImageURL: articleImageURL)
    }

    /// One public article announcement, independent of transport/message IDs.
    /// Audio announcements keep their existing, separate delivery identity.
    var articlePublicationID: String? {
        guard canPersist, let target, target.payload.isArticleNotification else { return nil }
        let id = target.identifier
        guard ArticleContentLanguage.isCMSArticleID(id) || ArticleContentLanguage.isEnglishArticleID(id) else { return nil }
        return "article-publication:" + id
    }
    var articlePublicationLanguage: ArticleContentLanguage? {
        guard articlePublicationID != nil, let target else { return nil }
        return ArticleContentLanguage.isEnglishArticleID(target.identifier) ? .english : .danish
    }
    var inboxIdentity: String {
        if let articlePublicationID { return articlePublicationID }
        // An unrelated delivery must not impersonate the reserved public row ID.
        guard id.hasPrefix("article-publication:") else { return id }
        let digest = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        return "notification-delivery:" + digest
    }

    static func publishedArticle(_ article: Article) -> Self? {
        guard article.hasValidContentIdentity, article.isPubliclyPublished, article.isDraft == false,
              let language = article.contentLanguage,
              (language == .danish ? ArticleContentLanguage.isCMSArticleID(article.id) : ArticleContentLanguage.isEnglishArticleID(article.id)),
              let published = Article.parseWebflowTimestamp(article.lastPublished),
              published.timeIntervalSince1970.isFinite,
              let name = article.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var info: [AnyHashable: Any] = ["type": "new_article", "article_id": article.id]
        if let slug = article.slug { info["article_slug"] = slug }
        let target = Target(identifier: article.id, slug: article.slug, type: "new_article")
        if let image = [article.thumbURL, article.mobileImageURL, article.coverURL]
            .compactMap({ Self.validatedArticleImageURL($0?.absoluteString, target: target) }).first {
            info["thumbnail_url"] = image.absoluteString
        }
        guard let item = make(id: "article-publication:" + article.id, title: name,
                              body: language == .english ? "Read the article" : "Læs artiklen",
                              date: published, userInfo: info), item.canPersist else { return nil }
        return item
    }

    /// Artwork is display metadata for an existing canonical article message.
    /// It cannot create a notification or confer publication/read authority.
    @MainActor
    static func enrichingArticleArtwork(_ items: [Self], from articles: [Article],
                                       stillCurrent: @MainActor () -> Bool = { true },
                                       permitsArticle: @MainActor (Article) -> Bool) -> [Self]? {
        guard items.count <= 100, articles.count <= 20_000, stillCurrent() else { return nil }
        let requested: Set<String> = Set(items.compactMap { $0.articlePublicationID == nil ? nil : $0.target?.identifier })
        var candidates: [String: Article] = [:]
        var ambiguous = Set<String>()
        for article in articles where requested.contains(article.id) {
            guard stillCurrent() else { return nil }
            if let previous = candidates[article.id], previous != article { ambiguous.insert(article.id) }
            candidates[article.id] = article
        }
        var result: [Self] = []
        for item in items {
            guard stillCurrent() else { return nil }
            guard let target = item.target, item.articlePublicationID != nil,
                  !ambiguous.contains(target.identifier), let article = candidates[target.identifier],
                  article.contentLanguage == item.articlePublicationLanguage,
                  (target.slug == nil || target.slug == article.slug),
                  permitsArticle(article) else { result.append(item); continue }
            guard stillCurrent() else { return nil }
            guard let published = publishedArticle(article) else { result.append(item); continue }
            result.append(item.replacingArticleImageURL(published.articleImageURL))
        }
        return stillCurrent() ? result : nil
    }

    fileprivate func replacingArticleImageURL(_ url: URL?) -> Self {
        .init(id: id, title: title, body: body, date: date, target: target,
              isRead: isRead, articleImageURL: url, origin: origin)
    }

    fileprivate func hasSameCanonicalArticleTarget(as other: Self) -> Bool {
        guard let identity = articlePublicationID, identity == other.articlePublicationID else { return false }
        if let slug = target?.slug, let otherSlug = other.target?.slug { return slug == otherSlug }
        return true
    }

    func identifiedForInbox() -> Self {
        let identity = inboxIdentity
        guard identity != id else { return self }
        return .init(id: identity, title: title, body: body, date: date,
                     target: target, isRead: isRead, articleImageURL: articleImageURL, origin: origin)
    }

    private static func validatedArticleImageURL(_ raw: String?, target: Target?) -> URL? {
        guard let target, ["new_article", "breaking_news", "new_narration"].contains(target.type),
              let raw, raw.utf8.count <= 2_048 else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed),
              url.absoluteString.utf8.count <= 2_048,
              NotificationImagePolicy.isAllowedURL(url) else { return nil }
        return url
    }
}

@MainActor
final class NotificationInboxModel: ObservableObject {
    struct Effects {
        var load: () throws -> Data?
        var save: (Data) throws -> Void
        var delivered: (@escaping @MainActor ([NotificationInboxItem]) -> Void) -> Void
        var removeDelivered: ([String]) -> Void
        var clearBadge: (@escaping @MainActor (Bool) -> Void) -> Void
        var open: (NotificationInboxItem.Target) -> Bool
        var setBadge: ((Int, @escaping @MainActor (Bool) -> Void) -> Void)? = nil
        var archiveLegacy: ((Data) throws -> Void)? = nil
        var now: () -> Date = Date.init
    }
    private struct Stored: Codable {
        let version: Int
        let items: [NotificationInboxItem]
        let read: [String]
        let dismissed: [String]
        var baselines: [String: [String]]? = nil
        var publicationFloors: [String: Date]? = nil
        var archived: [NotificationInboxItem]? = nil
        var badgeRead: [String]? = nil
        var badgeDeleted: [String]? = nil
    }
    static let maximumStorageBytes = 3 * 1024 * 1024
    struct BadgeInput: Sendable {
        let received: [NotificationUnreadStore.Event]
        let read: [String]
        let deleted: [String]
    }
    private var storedItems: [NotificationInboxItem] = []
    private(set) var items: [NotificationInboxItem] {
        get { storedItems }
        set { _ = publishItems(newValue) }
    }
    @Published private(set) var issue: String?
    @Published private(set) var refreshing = false
    private let effects: Effects
    private var read: [String] = []
    private var dismissed: [String] = []
    private var directRevision: [String: Int] = [:]
    private var revision = 0
    private var notifyingItems = false
    private var refreshID = UUID()
    private var badgeID = UUID()
    private var badgeInFlight = false
    private var desiredBadge = 0
    private var desiredBadgeRevision = 0
    private var badgeLanguage: ArticleContentLanguage = .danish
    private var baselines: [String: Set<String>] = [:]
    private var publicationFloors: [String: Date] = [:]
    private var archived: [NotificationInboxItem] = []
    private var badgeRead: [String] = []
    private var badgeDeleted: [String] = []
    private var pendingLegacyBytes: Data?
    private var storageReadable = true
    private var saveFailed = false
    private var badgeFailed = false
    var unreadCount: Int { items.filter { !$0.isRead }.count }

    init(effects: Effects) {
        self.effects = effects
        do {
            if let bytes = try effects.load() {
                guard bytes.count <= Self.maximumStorageBytes else { throw CocoaError(.coderReadCorrupt) }
                let value = try JSONDecoder().decode(Stored.self, from: bytes)
                guard [1, 2].contains(value.version), value.items.count <= 100,
                      value.read.count <= 200, value.dismissed.count <= 200,
                      value.items.allSatisfy(\.canPersist),
                      Set(value.items.map(\.id)).count == value.items.count,
                      Set(value.read).count == value.read.count,
                      Set(value.dismissed).count == value.dismissed.count,
                      (value.read + value.dismissed).allSatisfy({ $0.count == 64 && $0.allSatisfy { $0.isHexDigit } })
                else { throw CocoaError(.coderReadCorrupt) }
                let oldArchive = value.archived ?? []
                let known = value.baselines ?? [:]
                let floors = value.publicationFloors ?? [:]
                guard oldArchive.count <= 100, oldArchive.allSatisfy(\.canPersist),
                      Set(oldArchive.map(\.id)).count == oldArchive.count,
                      Self.validBaselineIDs(known),
                      (value.badgeRead?.count ?? 0) <= 200, (value.badgeDeleted?.count ?? 0) <= 200,
                      ((value.badgeRead ?? []) + (value.badgeDeleted ?? [])).allSatisfy(NotificationUnreadStore.isValidKey),
                      Set(floors.keys) == Set(known.keys), floors.values.allSatisfy({ $0.timeIntervalSince1970.isFinite }) else {
                    throw CocoaError(.coderReadCorrupt)
                }
                baselines = known.mapValues { Set($0) }; publicationFloors = floors
                archived = oldArchive; badgeRead = value.badgeRead ?? []; badgeDeleted = value.badgeDeleted ?? []
                if value.version == 1, value.items.contains(where: { $0.id == $0.articlePublicationID }) {
                    pendingLegacyBytes = bytes
                }
                read = value.read; dismissed = value.dismissed
                // A retained target can migrate its old transport marker exactly.
                // Already-deleted v1 records have only opaque hashes: retain those
                // hashes, but never invent an article association for them.
                for item in value.items {
                    if dismissed.contains(Self.key(item.id)) { remember(Self.key(item.inboxIdentity), in: &dismissed) }
                    if item.isRead || read.contains(Self.key(item.id)) { remember(Self.key(item.inboxIdentity), in: &read) }
                }
                for var item in value.items {
                    if value.version == 1, item.origin == nil, item.id != item.articlePublicationID { item.origin = .received }
                    merge(item)
                }
                sortAndBound()
            }
        } catch {
            storageReadable = false
            updateIssue()
        }
    }

    func refresh() {
        revision += 1
        let id = UUID(), started = revision
        refreshID = id; refreshing = true
        effects.delivered { [weak self] delivered in
            guard let self, self.refreshID == id else { return }
            let currentIDs = Set(delivered.map(\.inboxIdentity))
            self.items.removeAll { !$0.canPersist && !currentIDs.contains($0.id) && (self.directRevision[$0.id] ?? 0) <= started }
            for item in delivered.sorted(by: { $0.date > $1.date }).prefix(100)
                where (self.directRevision[item.inboxIdentity] ?? 0) <= started || self.archived.contains(where: { $0.id == item.inboxIdentity }) {
                    self.merge(self.received(item))
                }
            self.sortAndBound(); self.refreshing = false; self.persist(); self.synchronizeBadge()
        }
    }

    func receive(_ item: NotificationInboxItem, opened: Bool = false) {
        revision += 1; directRevision[item.inboxIdentity] = revision
        if opened { remember(Self.key(item.inboxIdentity), in: &read) }
        merge(received(item)); sortAndBound(); persist(); synchronizeBadge()
    }

    /// The caller supplies only its accepted fresh public namespaces. A cached
    /// feed, push permission or audio availability is never publication proof.
    func reconcilePublishedArticles(_ articles: [Article], stillCurrent: @MainActor () -> Bool,
                                    permitsArticle: @MainActor (Article) -> Bool) {
        reconcilePublishedArticles(articles, verifiedLanguages: Set(articles.compactMap(\.contentLanguage)),
                                   stillCurrent: stillCurrent, permitsArticle: permitsArticle)
    }

    func reconcilePublishedArticles(_ articles: [Article], verifiedLanguages: Set<ArticleContentLanguage>,
                                    receivedWitnesses: [NotificationUnreadStore.Event] = [],
                                    stillCurrent: @MainActor () -> Bool, permitsArticle: @MainActor (Article) -> Bool) {
        // A newer accepted attempt owns admission even when its result is empty.
        revision += 1
        let started = revision
        guard articles.count <= 20_000, receivedWitnesses.count <= 100,
              stillCurrent(), revision == started else { return }
        var candidates: [String: NotificationInboxItem] = [:]
        var sources: [String: Article] = [:]
        var ambiguous = Set<String>()
        for article in articles {
            guard stillCurrent(), revision == started else { return }
            guard permitsArticle(article) else { continue }
            guard stillCurrent(), revision == started else { return }
            guard let item = NotificationInboxItem.publishedArticle(article) else { continue }
            guard let language = article.contentLanguage, verifiedLanguages.contains(language) else { continue }
            if let previous = sources[article.id], previous != article { ambiguous.insert(article.id) }
            sources[article.id] = article; candidates[article.id] = item
        }
        var admitted: [NotificationInboxItem] = []
        for (id, item) in candidates where !ambiguous.contains(id) { admitted.append(item) }
        admitted.sort { left, right in
            if left.date == right.date { return left.id < right.id }
            return left.date > right.date
        }
        guard stillCurrent(), revision == started else { return }
        var nextBaselines = baselines
        var nextFloors = publicationFloors
        var nextBadgeDeleted = badgeDeleted
        var witnesses: [String: NotificationUnreadStore.Event] = [:]
        for event in receivedWitnesses where NotificationUnreadStore.isValidEvent(event) {
            if witnesses[event.key] == nil { witnesses[event.key] = event }
        }
        var announcements: [NotificationInboxItem] = []
        for language in verifiedLanguages {
            let rows = admitted.filter { $0.articlePublicationLanguage == language }
            let ids = Set(rows.compactMap { $0.target?.identifier })
            guard ids.count <= 10_000 else { return }
            if let previous = baselines[language.rawValue] {
                let combined = previous.union(ids)
                guard combined.count <= 10_000 else { return }
                nextBaselines[language.rawValue] = combined
                let floor = publicationFloors[language.rawValue] ?? .distantPast
                for var item in rows where witnesses[item.id] == nil && !previous.contains(item.target?.identifier ?? "") && item.date > floor {
                    item.origin = .publication; announcements.append(item)
                }
            } else {
                nextBaselines[language.rawValue] = ids
                nextFloors[language.rawValue] = rows.map(\.date).max() ?? effects.now()
            }
            for item in rows {
                guard let witness = witnesses[item.id], witness.languageCode == language.rawValue else { continue }
                announcements.append(.init(id: item.id, title: item.title, body: item.body, date: witness.date,
                    target: item.target, articleImageURL: item.articleImageURL, origin: .received))
            }
        }
        var proposed: [NotificationInboxItem] = items
        var nextArchive = archived
        let currentIDs = Set(admitted.compactMap { $0.target?.identifier })
        proposed.removeAll { item in
            guard item.origin == nil, item.id == item.articlePublicationID,
                  witnesses[item.id] == nil, let target = item.target, currentIDs.contains(target.identifier) else { return false }
            if !nextArchive.contains(where: { $0.id == item.id }) { nextArchive.append(item) }
            return true
        }
        guard nextArchive.count <= 100 else { return }
        for item in announcements {
            if dismissed.contains(Self.key(item.id)) {
                let key = NotificationUnreadStore.key(forInboxIdentity: item.id)
                if !nextBadgeDeleted.contains(key) { remember(key, in: &nextBadgeDeleted) }
            }
            merge(item, into: &proposed)
        }
        proposed.sort { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
        proposed = Array(proposed.prefix(100))
        // Known/read messages also receive current artwork, without becoming
        // new publications. Keep the same source/revision fence as admission.
        let artworkSources = sources.filter { !ambiguous.contains($0.key) }.map { $0.value }
        guard let enriched = NotificationInboxItem.enrichingArticleArtwork(proposed, from: artworkSources,
            stillCurrent: { stillCurrent() && self.revision == started }, permitsArticle: { _ in true }) else { return }
        let artworkIDs: [String] = zip(proposed, enriched).compactMap { before, after in
            before.articleImageURL != after.articleImageURL ? after.inboxIdentity : nil
        }
        proposed = enriched
        let admittedIDs: [String] = announcements.map { $0.inboxIdentity } + artworkIDs
        guard let committed = publishItems(proposed, expectedRevision: started, stillCurrent: stillCurrent,
                                           directIDs: admittedIDs, commitState: {
            self.baselines = nextBaselines; self.publicationFloors = nextFloors; self.archived = nextArchive
            self.badgeDeleted = nextBadgeDeleted
        }),
              stillCurrent(), revision == committed else { return }
        persist()
        if !announcements.isEmpty { synchronizeBadge() }
    }

    func visibleItems(language: ArticleContentLanguage) -> [NotificationInboxItem] {
        items.filter { $0.articlePublicationLanguage.map { $0 == language } ?? true }
    }
    func markRead(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        revision += 1
        remember(Self.key(id), in: &read); items[index].isRead = true
        remember(NotificationUnreadStore.key(forInboxIdentity: id), in: &badgeRead)
        persist(); effects.removeDelivered([id]); synchronizeBadge()
    }
    func markAllRead() {
        revision += 1
        let ids = items.map(\.id)
        for id in ids { remember(Self.key(id), in: &read) }
        for id in ids { remember(NotificationUnreadStore.key(forInboxIdentity: id), in: &badgeRead) }
        for index in items.indices { items[index].isRead = true }
        persist(); effects.removeDelivered(ids); synchronizeBadge()
    }
    func delete(_ id: String) {
        guard items.contains(where: { $0.id == id }) else { return }
        revision += 1
        remember(Self.key(id), in: &dismissed)
        remember(NotificationUnreadStore.key(forInboxIdentity: id), in: &badgeDeleted)
        items.removeAll { $0.id == id }; directRevision.removeValue(forKey: id)
        persist(); effects.removeDelivered([id]); synchronizeBadge()
    }
    @discardableResult func open(_ id: String) -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return false }
        if !item.isRead { markRead(id) }
        guard let target = item.target else { return false }
        return effects.open(target)
    }
    /// Kept for existing lifecycle callers: synchronize unread truth, never clear
    /// it merely because the app or inbox became visible.
    func clearBadge() { synchronizeBadge() }
    func synchronizeBadge(language: ArticleContentLanguage? = nil) {
        if let language { badgeLanguage = language }
        desiredBadgeRevision += 1
        desiredBadge = badgeInput.received.filter { $0.languageCode == nil || $0.languageCode == badgeLanguage.rawValue }.count
        drainBadge()
    }
    var badgeInput: BadgeInput {
        let events = items.filter { $0.canPersist && $0.origin != nil && !$0.isRead }.compactMap { item -> NotificationUnreadStore.Event? in
            guard let target = item.target else { return nil }
            var payload: [AnyHashable: Any] = [:]
            for (key, value) in NotificationNavigation.userInfo(for: target.payload) { payload[AnyHashable(key)] = value }
            return NotificationUnreadStore.event(userInfo: payload, requestIdentifier: item.id, date: item.date)
        }
        var reads = badgeRead
        for item in items where item.isRead {
            let key = NotificationUnreadStore.key(forInboxIdentity: item.id)
            if !reads.contains(key) { reads.append(key) }
        }
        if reads.count > 200 { reads.removeFirst(reads.count - 200) }
        return BadgeInput(received: events, read: reads, deleted: badgeDeleted)
    }
    private func drainBadge() {
        guard !badgeInFlight else { return }
        guard effects.setBadge != nil || desiredBadge == 0 else { return }
        badgeInFlight = true
        let sent = desiredBadge
        let sentRevision = desiredBadgeRevision
        let id = UUID(); badgeID = id
        let done: @MainActor (Bool) -> Void = { [weak self] success in
            guard let self, self.badgeID == id else { return }
            self.badgeInFlight = false
            if self.desiredBadgeRevision != sentRevision { self.drainBadge(); return }
            self.badgeFailed = !success
            self.updateIssue()
        }
        if let setBadge = effects.setBadge { setBadge(sent, done) }
        else { effects.clearBadge(done) }
    }
    private func received(_ source: NotificationInboxItem) -> NotificationInboxItem {
        var item = source
        if item.canPersist {
            item.origin = .received
            if dismissed.contains(Self.key(source.id)) || dismissed.contains(Self.key(source.inboxIdentity)) {
                let key = NotificationUnreadStore.key(forInboxIdentity: source.inboxIdentity)
                if !badgeDeleted.contains(key) { remember(key, in: &badgeDeleted) }
            }
        }
        return item
    }
    private func merge(_ source: NotificationInboxItem) {
        var proposed = items
        merge(source, into: &proposed)
        items = proposed
    }
    private func merge(_ source: NotificationInboxItem, into proposed: inout [NotificationInboxItem]) {
        guard !dismissed.contains(Self.key(source.id)), !dismissed.contains(Self.key(source.inboxIdentity)) else { return }
        var item = source.identifiedForInbox()
        item.isRead = read.contains(Self.key(source.id)) || read.contains(Self.key(item.id)) || source.isRead
        if source.origin == .received, let old = archived.first(where: { $0.id == item.id }) { item.isRead = item.isRead || old.isRead }
        if let index = proposed.firstIndex(where: { $0.id == item.id }) {
            item.isRead = item.isRead || proposed[index].isRead
            if proposed[index].origin == .received { item.origin = .received }
            // An older/no-image transport copy has no authority to erase cover
            // metadata for the same canonical article. Fresh article projection
            // separately replaces or clears it when that source is accepted.
            if item.articleImageURL == nil, item.hasSameCanonicalArticleTarget(as: proposed[index]) {
                item = item.replacingArticleImageURL(proposed[index].articleImageURL)
            }
            if item.articlePublicationID != nil {
                // A correction/bulk republish cannot make an old article new.
                item = .init(id: item.id, title: item.title, body: item.body,
                             date: min(item.date, proposed[index].date), target: item.target,
                             isRead: item.isRead, articleImageURL: item.articleImageURL, origin: item.origin)
            }
            proposed[index] = item
        }
        else { proposed.append(item) }
    }

    /// Notify before the plain-state assignment, then recheck both authority and
    /// revision. A willChange observer may revoke or publish newer state. No
    /// assignment or rollback runs after the final commit, so that newer state
    /// cannot be overwritten by a suspended setter or catchup loop.
    @discardableResult
    private func publishItems(_ proposed: [NotificationInboxItem], expectedRevision: Int? = nil,
                              stillCurrent: @MainActor () -> Bool = { true }, directIDs: [String] = [],
                              commitState: (() -> Void)? = nil) -> Int? {
        let original = revision
        guard expectedRevision.map({ $0 == original }) ?? true,
              stillCurrent(), revision == original else { return nil }
        if storedItems != proposed {
            if !notifyingItems {
                notifyingItems = true
                objectWillChange.send()
                notifyingItems = false
            }
            guard revision == original, stillCurrent(), revision == original else { return nil }
            revision += 1
            commitState?()
            for id in directIDs { directRevision[id] = revision }
            storedItems = proposed
        } else if !directIDs.isEmpty || commitState != nil {
            // An unchanged but newly accepted publication still fences an older
            // delivered-notification snapshot without emitting an item update.
            revision += 1
            commitState?()
            for id in directIDs { directRevision[id] = revision }
        }
        let retained = Set(storedItems.map(\.id))
        directRevision = directRevision.filter { retained.contains($0.key) }
        return revision
    }
    private func sortAndBound() {
        items.sort { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
        items = Array(items.prefix(100))
        let ids = Set(items.map(\.id)); directRevision = directRevision.filter { ids.contains($0.key) }
    }
    private func persist() {
        guard storageReadable else { return }
        do {
            if let bytes = pendingLegacyBytes {
                guard let archive = effects.archiveLegacy else { throw CocoaError(.fileWriteNoPermission) }
                try archive(bytes); pendingLegacyBytes = nil
            }
            let value = Stored(version: 2, items: items.filter(\.canPersist), read: read, dismissed: dismissed,
                               baselines: baselines.mapValues { Array($0).sorted() }, publicationFloors: publicationFloors,
                               archived: archived, badgeRead: badgeRead, badgeDeleted: badgeDeleted)
            let bytes = try JSONEncoder().encode(value)
            guard bytes.count <= Self.maximumStorageBytes else { throw CocoaError(.fileWriteOutOfSpace) }
            try effects.save(bytes)
            saveFailed = false
            updateIssue()
        } catch { saveFailed = true; updateIssue() }
    }
    private func updateIssue() {
        let next: String?
        if !storageReadable {
            next = "Gemte meddelelser kunne ikke læses. Nye beskeder vises midlertidigt."
        } else if saveFailed {
            next = "Ændringen kunne ikke gemmes på denne enhed."
        } else if badgeFailed {
            next = "Appens røde tal kunne ikke opdateres. Prøv igen."
        } else { next = nil }
        if issue != next { issue = next }
    }
    private func remember(_ value: String, in values: inout [String]) {
        values.removeAll { $0 == value }; values.append(value)
        if values.count > 200 { values.removeFirst(values.count - 200) }
    }
    private static func validBaselineIDs(_ known: [String: [String]]) -> Bool {
        for (code, ids) in known {
            guard let language = ArticleContentLanguage(rawValue: code), ids.count <= 10_000,
                  Set(ids).count == ids.count else { return false }
            for id in ids {
                let valid = language == .english ? ArticleContentLanguage.isEnglishArticleID(id) : ArticleContentLanguage.isCMSArticleID(id)
                if !valid { return false }
            }
        }
        return true
    }
    private static func key(_ id: String) -> String {
        SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
