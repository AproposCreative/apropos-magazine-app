import CryptoKit
import Foundation
import UserNotifications

/// Only local notification-center effects. Construction does not initialize
/// Firebase, APNs registration, analytics or any production transport.
@MainActor
enum NotificationInboxRuntime {
    private static let badgeQueue = DispatchQueue(label: "apropos.notifications.unread")
    static let model: NotificationInboxModel = NotificationInboxModel(effects: .init(
        load: {
            let url = try storageURL()
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard ((attributes[.size] as? NSNumber)?.intValue ?? 0) <= NotificationInboxModel.maximumStorageBytes else {
                throw CocoaError(.fileReadTooLarge)
            }
            return try Data(contentsOf: url)
        },
        save: { bytes in
            let url = try storageURL()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: url, options: .atomic)
        },
        delivered: { done in
            UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
                let values = notifications.compactMap(NotificationInboxItem.from)
                Task { @MainActor in done(withCurrentArticleArtwork(values)) }
            }
        },
        removeDelivered: { identifiers in
            let center = UNUserNotificationCenter.current()
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
            let semanticIDs = Set(identifiers.filter {
                $0.hasPrefix("article-publication:") || $0.hasPrefix("notification-delivery:")
            })
            guard !semanticIDs.isEmpty else { return }
            // Canonical inbox IDs survive a cold start; UN transport IDs do not
            // have to be persisted to remove the corresponding delivered alerts.
            center.getDeliveredNotifications { notifications in
                let matches = notifications.filter { notification in
                    NotificationInboxItem.from(notification).map { semanticIDs.contains($0.inboxIdentity) } == true
                }.map { $0.request.identifier }
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: matches)
            }
        },
        clearBadge: { done in
            // Legacy injection compatibility only. Live effects always provide
            // the counted setter below; no fallback is allowed to force zero.
            Task { @MainActor in done(false) }
        },
        open: { IncomingLinkRuntime.shared.acceptNotification($0.payload) },
        setBadge: { _, done in
            let work = MainActor.assumeIsolated { (model.badgeInput, badgeQueue) }
            work.1.async {
                do {
                    let store = try unreadStore()
                    let language = badgeLanguageCode()
                    let projection = try store.apply(received: work.0.received, read: work.0.read,
                                                     deleted: work.0.deleted, languageCode: language)
                    UNUserNotificationCenter.current().setBadgeCount(projection.count) { error in
                        work.1.async {
                            let latest = try? store.snapshot(languageCode: badgeLanguageCode())
                            // A failed read is an error, not evidence of new state.
                            // Retry only a successfully observed concurrent change.
                            let changed = latest.map { $0.revision != projection.revision || $0.count != projection.count } ?? false
                            Task { @MainActor in
                                done(error == nil && latest != nil)
                                // A concurrent extension receipt/read must not
                                // leave this completed OS write at an old count.
                                if changed { model.synchronizeBadge(language: currentBadgeLanguage()) }
                            }
                        }
                    }
                } catch { Task { @MainActor in done(false) } }
            }
        }, archiveLegacy: { bytes in
            try MainActor.assumeIsolated { try archiveLegacyBytes(bytes) }
        }
    ))
    private static func storageURL() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: false)
        return base.appendingPathComponent("AproposNotifications", isDirectory: true)
            .appendingPathComponent("public-inbox-v1.json", isDirectory: false)
    }
    static func didBecomeActive() { model.refresh() }
    static func reconcilePublishedArticles(_ articles: [Article], stillCurrent: @escaping @MainActor () -> Bool) async {
        await reconcilePublishedArticles(articles, verifiedLanguages: Set(articles.compactMap(\.contentLanguage)), stillCurrent: stillCurrent)
    }
    static func reconcilePublishedArticles(_ articles: [Article], verifiedLanguages: Set<ArticleContentLanguage>,
                                          stillCurrent: @escaping @MainActor () -> Bool) async {
        guard stillCurrent() else { return }
        let witnesses: [NotificationUnreadStore.Event] = await withCheckedContinuation { continuation in
            badgeQueue.async {
                let events = (try? unreadStore().snapshot(languageCode: badgeLanguageCode()).unread) ?? []
                continuation.resume(returning: events)
            }
        }
        guard stillCurrent() else { return }
        model.reconcilePublishedArticles(articles, verifiedLanguages: verifiedLanguages,
            receivedWitnesses: witnesses, stillCurrent: stillCurrent,
            permitsArticle: { ArticleAvailabilityService.model.permitsBody($0) })
    }
    static func synchronizeBadge() { model.refresh() }
    static func clearBadge() { synchronizeBadge() }
    static func receive(_ notification: UNNotification, opened: Bool) {
        guard let item = NotificationInboxItem.from(notification) else { synchronizeBadge(); return }
        model.receive(withCurrentArticleArtwork([item]).first ?? item, opened: opened)
    }

    private static func withCurrentArticleArtwork(_ items: [NotificationInboxItem]) -> [NotificationInboxItem] {
        // Memory-only lookup: no fetch, hydration, SDK read or new publication.
        // The existing cache and availability boundary strips obsolete metadata.
        guard let articles = CacheManager.shared.getCachedArticles() else { return items }
        return NotificationInboxItem.enrichingArticleArtwork(items, from: articles,
            permitsArticle: { ArticleAvailabilityService.model.permitsBody($0) }) ?? items
    }

    private nonisolated static func badgeLanguageCode() -> String {
        UserDefaults(suiteName: NotificationUnreadStore.appGroupID)?.string(forKey: NotificationUnreadStore.languagePreferenceKey) == "en" ? "en" : "da"
    }
    private static func currentBadgeLanguage() -> ArticleContentLanguage { badgeLanguageCode() == "en" ? .english : .danish }
    private nonisolated static func unreadStore() throws -> NotificationUnreadStore {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: NotificationUnreadStore.appGroupID) else {
            throw NotificationUnreadStore.Failure.unavailable
        }
        return NotificationUnreadStore(directory: group.appendingPathComponent("NotificationUnread", isDirectory: true))
    }
    private static func archiveLegacyBytes(_ bytes: Data) throws {
        try archiveLegacyBytes(bytes, directory: storageURL().deletingLastPathComponent())
    }
    static func archiveLegacyBytes(_ bytes: Data, directory: URL) throws {
        guard bytes.count <= 1_500_000 else { throw CocoaError(.fileReadTooLarge) }
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let archive = directory.appendingPathComponent("public-inbox-pre155-" + digest + ".json")
        if FileManager.default.fileExists(atPath: archive.path) {
            let values = try archive.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, values.fileSize == bytes.count,
                  try Data(contentsOf: archive) == bytes else { throw CocoaError(.fileReadCorruptFile) }
        } else {
            try bytes.write(to: archive, options: .withoutOverwriting)
        }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: archive.path)
        #endif
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var destination = archive; try destination.setResourceValues(values)
    }
}

extension NotificationInboxItem {
    static func from(_ notification: UNNotification) -> Self? {
        let content = notification.request.content
        return make(id: notification.request.identifier, title: content.title, body: content.body,
                    date: notification.date, userInfo: content.userInfo)
    }
}
