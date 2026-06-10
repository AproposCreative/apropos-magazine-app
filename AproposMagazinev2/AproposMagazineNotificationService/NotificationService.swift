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
    
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?
    
    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        guard let bestAttemptContent = bestAttemptContent else {
            contentHandler(request.content)
            return
        }
        
        var articleId: String?
        if let id = bestAttemptContent.userInfo["article_id"] as? String, !id.isEmpty {
            articleId = id
        } else if let slug = bestAttemptContent.userInfo["article_slug"] as? String, !slug.isEmpty {
            articleId = slug
        } else if let dataDict = bestAttemptContent.userInfo["data"] as? [String: Any],
                  let id = dataDict["article_id"] as? String, !id.isEmpty {
            articleId = id
        }
        
        // Get thumbnail URL from userInfo (supports FCM data + APNS payload nesting)
        let thumbnailURL = Self.imageURL(from: bestAttemptContent.userInfo)
        
        guard let imageURL = thumbnailURL else {
            // No thumbnail URL available, send notification without attachment
            contentHandler(bestAttemptContent)
            return
        }
        
        // Download thumbnail image
        downloadImage(from: imageURL) { attachmentURL in
            guard let attachmentURL = attachmentURL else {
                // Download failed, send notification without attachment
                contentHandler(bestAttemptContent)
                return
            }
            
            // Create attachment
            do {
                let attachmentId = articleId ?? "unknown"
                let attachment = try UNNotificationAttachment(
                    identifier: "article-thumbnail-\(attachmentId)",
                    url: attachmentURL,
                    options: [
                        UNNotificationAttachmentOptionsTypeHintKey: "public.jpeg",
                        UNNotificationAttachmentOptionsThumbnailHiddenKey: false
                    ]
                )
                
                bestAttemptContent.attachments = [attachment]
                contentHandler(bestAttemptContent)
            } catch {
                // Send notification without attachment if attachment creation fails
                contentHandler(bestAttemptContent)
            }
        }
    }
    
    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system
        // Use this to clean up and deliver the notification as-is
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
    
    // MARK: - Image Download

    private static func imageURL(from userInfo: [AnyHashable: Any]) -> URL? {
        let candidateKeys = ["thumbnail_url", "cover_url", "image"]

        for key in candidateKeys {
            if let value = userInfo[key] as? String,
               let url = URL(string: value),
               !value.isEmpty {
                return url
            }
        }

        if let data = userInfo["data"] as? [String: Any] {
            for key in candidateKeys {
                if let value = data[key] as? String,
                   let url = URL(string: value),
                   !value.isEmpty {
                    return url
                }
            }
        }

        if let fcmOptions = userInfo["fcm_options"] as? [String: Any],
           let image = fcmOptions["image"] as? String,
           let url = URL(string: image),
           !image.isEmpty {
            return url
        }

        return nil
    }
    
    private func downloadImage(from url: URL, completion: @escaping (URL?) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { localURL, response, error in
            guard let localURL = localURL, error == nil else {
                completion(nil)
                return
            }
            
            // Move file to a temporary directory with proper file extension
            let tempDir = FileManager.default.temporaryDirectory
            let fileExtension = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
            let fileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(fileExtension)
            
            do {
                // Remove file if it already exists
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                
                // Move downloaded file to temp directory
                try FileManager.default.moveItem(at: localURL, to: fileURL)
                completion(fileURL)
            } catch {
                completion(nil)
            }
        }
        
        task.resume()
    }
}

