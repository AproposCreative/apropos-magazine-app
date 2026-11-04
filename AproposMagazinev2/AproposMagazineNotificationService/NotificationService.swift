//
//  NotificationService.swift
//  AproposMagazineNotificationService
//
//  Notification Service Extension for Rich Notifications
//  Downloads article thumbnails and adds them as attachments
//

import UserNotifications
import Foundation

// MARK: - Shared Models (must match main app)

/// Cache data structure for sharing between app and extension
private struct CacheData: Codable {
    let articles: [ArticleCacheItem]
    let timestamp: Date
    let version: String
}

/// Simplified article cache item for extension (only fields needed for publication check)
private struct ArticleCacheItem: Codable {
    let id: String
    let lastPublished: String?
    let createdOn: String?
    
    var publishedDate: Date? {
        guard let lastPublished = lastPublished else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: lastPublished) {
            return date
        }
        // Try alternative formats
        let altFormatters: [DateFormatter] = [
            { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"; return f }(),
            { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"; return f }()
        ]
        for formatter in altFormatters {
            if let date = formatter.date(from: lastPublished) {
                return date
            }
        }
        return nil
    }
    
    var createdDate: Date? {
        guard let createdOn = createdOn else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: createdOn) {
            return date
        }
        let altFormatters: [DateFormatter] = [
            { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"; return f }(),
            { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"; return f }()
        ]
        for formatter in altFormatters {
            if let date = formatter.date(from: createdOn) {
                return date
            }
        }
        return nil
    }
}

class NotificationServiceExtension: UNNotificationServiceExtension {
    private let deliveryLock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?
    private var imageDownloader: NotificationImageDownloader?
    private var unreadStore: NotificationUnreadStore?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        let content: UNMutableNotificationContent
        if let mutable = request.content.mutableCopy() as? UNMutableNotificationContent {
            content = mutable
        } else {
            // Preserve visible delivery even for an unexpected immutable copy.
            let original = request.content
            content = UNMutableNotificationContent()
            content.title = original.title; content.subtitle = original.subtitle; content.body = original.body
            content.sound = original.sound; content.categoryIdentifier = original.categoryIdentifier
            content.threadIdentifier = original.threadIdentifier; content.userInfo = original.userInfo
            content.attachments = original.attachments; content.launchImageName = original.launchImageName
            content.interruptionLevel = original.interruptionLevel; content.relevanceScore = original.relevanceScore
            content.targetContentIdentifier = original.targetContentIdentifier
        }
        // A missing badge preserves the current system value if the local
        // shared state cannot be read. Only actual received editorial messages
        // can add an unread event; a feed inventory is never a delivery.
        content.badge = nil

        deliveryLock.lock()
        self.contentHandler = contentHandler
        bestAttemptContent = content
        deliveryLock.unlock()

        UNUserNotificationCenter.current().getDeliveredNotifications { [weak self] delivered in
            self?.registerUnreadAndEnrich(request: request, delivered: delivered)
        }
    }

    private func registerUnreadAndEnrich(request: UNNotificationRequest, delivered: [UNNotification]) {
        let incoming = NotificationUnreadStore.event(userInfo: request.content.userInfo,
            requestIdentifier: request.identifier, date: Date())
        let existing = delivered.compactMap {
            NotificationUnreadStore.event(userInfo: $0.request.content.userInfo,
                requestIdentifier: $0.request.identifier, date: $0.date)
        }.sorted { $0.date > $1.date }
        let events = Array(existing.prefix(incoming == nil ? 100 : 99)) + (incoming.map { [$0] } ?? [])
        deliveryLock.lock()
        guard contentHandler != nil, let content = bestAttemptContent else {
            deliveryLock.unlock(); return
        }
        if let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: NotificationUnreadStore.appGroupID) {
            let store = NotificationUnreadStore(directory: directory.appendingPathComponent("NotificationUnread", isDirectory: true))
            unreadStore = store
            content.badge = (try? store.apply(received: events, languageCode: Self.badgeLanguageCode()))
                .map { NSNumber(value: $0.count) }
        }
        deliveryLock.unlock()
        beginImageEnrichment(content: content)
    }

    private static func badgeLanguageCode() -> String {
        UserDefaults(suiteName: NotificationUnreadStore.appGroupID)?.string(forKey: NotificationUnreadStore.languagePreferenceKey) == "en" ? "en" : "da"
    }

    private func beginImageEnrichment(content: UNMutableNotificationContent) {
        guard let imageURL = Self.imageURL(from: content.userInfo) else {
            finish()
            return
        }

        let downloader = NotificationImageDownloader(url: imageURL) { [weak self] image in
            guard let self else { return }
            guard let image else {
                self.finish()
                return
            }

            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(image.format.fileExtension)

            do {
                try image.data.write(to: fileURL, options: .atomic)
                let attachment = try UNNotificationAttachment(
                    identifier: "article-thumbnail",
                    url: fileURL,
                    options: [
                        UNNotificationAttachmentOptionsTypeHintKey: image.format.typeIdentifier,
                        UNNotificationAttachmentOptionsThumbnailHiddenKey: false
                    ]
                )
                // Keep delivered files readable until the system has moved
                // them into its attachment store. Delete only rejected work.
                if !self.finish(attachment: attachment) {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            } catch {
                try? FileManager.default.removeItem(at: fileURL)
                self.finish()
            }
        }

        deliveryLock.lock()
        // Expiry may have delivered fallback content while the downloader was
        // being created. Never start work after delivery has been consumed.
        if self.contentHandler != nil {
            imageDownloader = downloader
            downloader.start()
        }
        deliveryLock.unlock()
    }

    override func serviceExtensionTimeWillExpire() {
        finish()
    }

    /// The timeout callback runs on a separate thread. Consume the handler and
    /// content together under a lock so timeout and download completion cannot
    /// both deliver or mutate content already handed to the system.
    @discardableResult
    private func finish(attachment: UNNotificationAttachment? = nil) -> Bool {
        deliveryLock.lock()
        guard let handler = contentHandler, let content = bestAttemptContent else {
            deliveryLock.unlock()
            return false
        }
        contentHandler = nil
        bestAttemptContent = nil
        // An app tap may have acknowledged the event during image loading.
        // Reproject under the shared lock immediately before handing off.
        content.badge = unreadStore.flatMap { try? $0.snapshot(languageCode: Self.badgeLanguageCode()) }
            .map { NSNumber(value: $0.count) }
        if let attachment {
            content.attachments = [attachment]
        }
        let downloader = imageDownloader
        imageDownloader = nil
        deliveryLock.unlock()

        downloader?.cancel()
        handler(content)
        return true
    }

    private static func imageURL(from userInfo: [AnyHashable: Any]) -> URL? {
        let candidateKeys = ["thumbnail_url", "cover_url", "image"]
        var candidates = candidateKeys.compactMap { userInfo[$0] as? String }
        if let data = userInfo["data"] as? [String: Any] {
            candidates += candidateKeys.compactMap { data[$0] as? String }
        }
        if let fcmOptions = userInfo["fcm_options"] as? [String: Any],
           let image = fcmOptions["image"] as? String {
            candidates.append(image)
        }

        for candidate in candidates {
            guard let url = URL(string: candidate), NotificationImagePolicy.isAllowedURL(url) else { continue }
            return url
        }
        return nil
    }
}

private final class NotificationImageDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    struct Image {
        let data: Data
        let format: NotificationImagePolicy.Format
    }

    private let url: URL
    private let stateLock = NSLock()
    private var completion: ((Image?) -> Void)?
    private var session: URLSession?
    private var receivedData = Data()
    private var mimeType: String?
    private var redirectCount = 0

    init(url: URL, completion: @escaping (Image?) -> Void) {
        self.url = url
        self.completion = completion
    }

    func start() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = NotificationImagePolicy.requestTimeout
        configuration.timeoutIntervalForResource = NotificationImagePolicy.resourceTimeout
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        stateLock.lock()
        guard completion != nil, session == nil else {
            stateLock.unlock()
            return
        }
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session
        let task = session.dataTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        task.resume()
        stateLock.unlock()
    }

    func cancel() {
        stateLock.lock()
        completion = nil
        receivedData.removeAll()
        let session = self.session
        self.session = nil
        stateLock.unlock()
        session?.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        stateLock.lock()
        let allowed = completion != nil && redirectCount < 3
            && request.url.map(NotificationImagePolicy.isAllowedURL) == true
        if allowed { redirectCount += 1 }
        stateLock.unlock()
        completionHandler(allowed ? request : nil)
        if !allowed { finish(nil) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse,
              let url = response.url,
              NotificationImagePolicy.isAllowedURL(url),
              NotificationImagePolicy.allowsResponse(
                statusCode: response.statusCode,
                mimeType: response.mimeType,
                expectedLength: response.expectedContentLength
              ) else {
            completionHandler(.cancel)
            finish(nil)
            return
        }
        stateLock.lock()
        mimeType = response.mimeType
        let active = completion != nil
        stateLock.unlock()
        completionHandler(active ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        stateLock.lock()
        guard completion != nil else {
            stateLock.unlock()
            return
        }
        // Enforce the cap while streaming, including chunked responses or
        // servers that underreport Content-Length.
        guard data.count <= NotificationImagePolicy.maximumBytes - receivedData.count else {
            stateLock.unlock()
            finish(nil)
            return
        }
        receivedData.append(data)
        stateLock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        stateLock.lock()
        let data = receivedData
        let mimeType = self.mimeType
        let active = completion != nil
        stateLock.unlock()
        guard active else { return }
        guard error == nil,
              let format = NotificationImagePolicy.validatedFormat(for: data, mimeType: mimeType) else {
            finish(nil)
            return
        }
        finish(Image(data: data, format: format))
    }

    private func finish(_ image: Image?) {
        stateLock.lock()
        let completion = self.completion
        self.completion = nil
        receivedData.removeAll()
        let session = self.session
        self.session = nil
        stateLock.unlock()
        session?.invalidateAndCancel()
        completion?(image)
    }
}
