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
        print("🔔 [NotificationServiceExtension] didReceive called!")
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        guard let bestAttemptContent = bestAttemptContent else {
            print("⚠️ [NotificationServiceExtension] bestAttemptContent is nil")
            contentHandler(request.content)
            return
        }
        
        print("🔍 [NotificationServiceExtension] userInfo keys: \(bestAttemptContent.userInfo.keys)")
        
        // Check if this is an article notification
        // Try to get article_id from userInfo (required for duplicate check)
        // FCM sends data in the 'data' field, which iOS converts to userInfo
        
        var articleId: String?
        if let id = bestAttemptContent.userInfo["article_id"] as? String, !id.isEmpty {
            articleId = id
        } else if let slug = bestAttemptContent.userInfo["article_slug"] as? String, !slug.isEmpty {
            articleId = slug
        } else {
            // Check if data is nested in 'data' field (some FCM configurations)
            if let dataDict = bestAttemptContent.userInfo["data"] as? [String: Any],
               let id = dataDict["article_id"] as? String, !id.isEmpty {
                articleId = id
            }
        }
        
        // CRITICAL: Check if article is already published BEFORE processing
        // This prevents duplicate notifications when articles are updated
        if let articleId = articleId, !articleId.isEmpty {
            print("🔍 [NotificationServiceExtension] Checking article: \(articleId)")
            let isAlreadyPublished = isArticleAlreadyPublished(articleId: articleId)
            print("🔍 [NotificationServiceExtension] isAlreadyPublished: \(isAlreadyPublished)")
            
            if isAlreadyPublished {
                print("🚫 [NotificationServiceExtension] BLOCKING notification - article \(articleId) already published (exists in cache)")
                // Article is already published - return empty notification to suppress it
                let emptyContent = UNMutableNotificationContent()
                emptyContent.title = ""
                emptyContent.body = ""
                emptyContent.sound = nil
                emptyContent.badge = nil
                contentHandler(emptyContent)
                return
            } else {
                print("✅ [NotificationServiceExtension] ALLOWING notification - article \(articleId) is NEW (not in cache)")
            }
        } else {
            print("⚠️ [NotificationServiceExtension] articleId is missing or empty - cannot check cache")
            // No article_id provided - try to find article by name as fallback
            // This happens when backend doesn't send article_id (e.g., when republishing in Webflow)
            
            // Try to find article by name as fallback
            if let articleName = bestAttemptContent.userInfo["article_name"] as? String, !articleName.isEmpty {
                // Try to find article in cache by name and get its ID
                if let foundArticleId = findArticleIdByName(articleName: articleName) {
                    // Now we have article_id - use it for duplicate check
                    let isAlreadyPublished = isArticleAlreadyPublished(articleId: foundArticleId)
                    
                    if isAlreadyPublished {
                        let emptyContent = UNMutableNotificationContent()
                        emptyContent.title = ""
                        emptyContent.body = ""
                        emptyContent.sound = nil
                        emptyContent.badge = nil
                        contentHandler(emptyContent)
                        return
                    }
                }
            }
            // Continue to show notification (either new article or can't determine)
        }
        
        // Get thumbnail URL from userInfo
        var thumbnailURL: URL?
        
        if let thumbnailURLString = bestAttemptContent.userInfo["thumbnail_url"] as? String,
           let url = URL(string: thumbnailURLString) {
            thumbnailURL = url
        } else if let coverURLString = bestAttemptContent.userInfo["cover_url"] as? String,
                  let url = URL(string: coverURLString) {
            // Fallback to cover URL if thumbnail not available
            thumbnailURL = url
        }
        
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
    
    // MARK: - Article Publication Check
    
    /// Check if an article is already published (has publishedDate in the past)
    /// Uses App Group UserDefaults to access cached articles from main app
    private func isArticleAlreadyPublished(articleId: String) -> Bool {
        print("🔍 [NotificationServiceExtension] Checking if article \(articleId) is already published...")
        
        // Try App Group UserDefaults first (preferred method)
        if let appGroupDefaults = UserDefaults(suiteName: "group.com.aproposmagazine.app") {
            print("✅ [NotificationServiceExtension] App Group UserDefaults accessible")
            
            if let data = appGroupDefaults.data(forKey: "cached_articles"),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let articlesArray = json["articles"] as? [[String: Any]] {
                
                print("✅ [NotificationServiceExtension] Found \(articlesArray.count) articles in cache")
                
                // Find article in simplified cache
                // Try exact match first
                if let articleDict = articlesArray.first(where: { ($0["id"] as? String) == articleId }) {
                    print("✅ [NotificationServiceExtension] Article \(articleId) FOUND in cache - already published!")
                    let now = Date()
                    
                    // CRITICAL: If article exists in cache, it means it was already published before
                    // The cache only contains published articles that have been fetched from Webflow API
                    // If an article is in cache, it means it was already published and fetched by the app
                    // Therefore, this is a republish - don't send notification
                    print("🚫 [NotificationServiceExtension] Article \(articleId) exists in cache - already published before, blocking notification")
                    return true
                } else {
                    print("⚠️ [NotificationServiceExtension] Article \(articleId) NOT found in App Group cache")
                }
            } else {
                print("⚠️ [NotificationServiceExtension] No cache data in App Group")
            }
        } else {
            print("⚠️ [NotificationServiceExtension] App Group UserDefaults NOT accessible - trying standard UserDefaults")
            
            // Fallback: Try standard UserDefaults (if App Group not available)
            if let data = UserDefaults.standard.data(forKey: "cached_articles"),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let articlesArray = json["articles"] as? [[String: Any]] {
                
                print("✅ [NotificationServiceExtension] Found \(articlesArray.count) articles in standard UserDefaults")
                
                if let articleDict = articlesArray.first(where: { ($0["id"] as? String) == articleId }) {
                    print("✅ [NotificationServiceExtension] Article \(articleId) FOUND in standard cache - already published!")
                    let now = Date()
                    
                    // CRITICAL: If article exists in cache, it means it was already published before
                    // The cache only contains published articles that have been fetched from Webflow API
                    // If an article is in cache, it means it was already published and fetched by the app
                    // Therefore, this is a republish - don't send notification
                    print("🚫 [NotificationServiceExtension] Article \(articleId) exists in standard cache - already published before, blocking notification")
                    return true
                } else {
                    print("⚠️ [NotificationServiceExtension] Article \(articleId) NOT found in standard cache")
                }
            } else {
                print("⚠️ [NotificationServiceExtension] No cache data in standard UserDefaults")
            }
        }
        
        // Article not found or dates are in future - assume it's new
        print("✅ [NotificationServiceExtension] Article \(articleId) NOT found in cache - treating as NEW")
        return false
    }
    
    /// Find article ID by name in cache (fallback when article_id is missing from notification)
    /// Returns article_id if found, nil otherwise
    private func findArticleIdByName(articleName: String) -> String? {
        // Try App Group UserDefaults first
        if let appGroupDefaults = UserDefaults(suiteName: "group.com.aproposmagazine.app"),
           let data = appGroupDefaults.data(forKey: "cached_articles"),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let articlesArray = json["articles"] as? [[String: Any]] {
            
            // Search for article by name (case-insensitive)
            let searchName = articleName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            
            // First try exact match
            if let articleDict = articlesArray.first(where: { 
                if let name = $0["name"] as? String {
                    return name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == searchName
                }
                return false
            }), let articleId = articleDict["id"] as? String, !articleId.isEmpty {
                return articleId
            }
            
            // Try partial match (contains) - but be more strict
            if let articleDict = articlesArray.first(where: { 
                if let name = $0["name"] as? String {
                    let normalizedName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    // Check if searchName is contained in name or vice versa (but not too short)
                    return (normalizedName.contains(searchName) || searchName.contains(normalizedName)) && searchName.count >= 3
                }
                return false
            }), let articleId = articleDict["id"] as? String, !articleId.isEmpty {
                return articleId
            }
        }
        
        // Fallback: Try standard UserDefaults
        if let data = UserDefaults.standard.data(forKey: "cached_articles"),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let articlesArray = json["articles"] as? [[String: Any]] {
            
            let searchName = articleName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let articleDict = articlesArray.first(where: { 
                if let name = $0["name"] as? String {
                    let normalizedName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    return normalizedName == searchName || 
                           (normalizedName.contains(searchName) || searchName.contains(normalizedName)) && searchName.count >= 3
                }
                return false
            }), let articleId = articleDict["id"] as? String, !articleId.isEmpty {
                return articleId
            }
        }
        
        return nil
    }
    
    /// Parse date string to Date object
    private func parseDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date
        }
        // Try alternative formats
        let altFormatters: [DateFormatter] = [
            { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"; return f }(),
            { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"; return f }()
        ]
        for formatter in altFormatters {
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        return nil
    }
    
    // MARK: - Image Download
    
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

