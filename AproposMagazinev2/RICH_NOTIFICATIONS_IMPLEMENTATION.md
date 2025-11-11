# Rich Notifications Implementation Guide

## Oversigt

Rich Notifications giver mulighed for at vise billeder, video previews og custom UI i notifikationer. Dette gør notifikationer mere visuelt tiltalende og øger brugerengagement.

## Arkitektur

Rich Notifications kræver to komponenter:

1. **NotificationServiceExtension** - Håndterer tilføjelse af attachments (billeder, video) til notifikationer
2. **NotificationContentExtension** (valgfrit) - Giver custom UI til notifikationer

## Implementeringsplan

### Fase 1: NotificationServiceExtension

#### 1.1 Opret NotificationServiceExtension Target

1. Åbn Xcode
2. File → New → Target
3. Vælg "Notification Service Extension"
4. Navn: `AproposMagazineNotificationService`
5. Bundle Identifier: `com.aproposmagazine.app.AproposMagazineNotificationService`
6. Language: Swift

#### 1.2 Konfigurer NotificationServiceExtension

NotificationServiceExtension skal:
- Modtage notifikationer fra Firebase/APNs
- Downloade artikel thumbnail
- Tilføje thumbnail som `UNNotificationAttachment`
- Sende notifikationen videre

#### 1.3 Implementer Attachment Download

```swift
// NotificationService.swift (i NotificationServiceExtension target)
import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        guard let bestAttemptContent = bestAttemptContent else { return }
        
        // Hent artikel thumbnail URL fra userInfo
        if let articleId = bestAttemptContent.userInfo["article_id"] as? String,
           let thumbnailURL = bestAttemptContent.userInfo["thumbnail_url"] as? String,
           let url = URL(string: thumbnailURL) {
            
            // Download thumbnail
            downloadImage(from: url) { [weak self] imageURL in
                guard let self = self,
                      let imageURL = imageURL else {
                    contentHandler(bestAttemptContent)
                    return
                }
                
                // Opret attachment
                do {
                    let attachment = try UNNotificationAttachment(
                        identifier: "article-thumbnail",
                        url: imageURL,
                        options: nil
                    )
                    bestAttemptContent.attachments = [attachment]
                } catch {
                    print("Kunne ikke oprette attachment: \(error)")
                }
                
                contentHandler(bestAttemptContent)
            }
        } else {
            contentHandler(bestAttemptContent)
        }
    }
    
    private func downloadImage(from url: URL, completion: @escaping (URL?) -> Void) {
        URLSession.shared.downloadTask(with: url) { localURL, _, error in
            guard let localURL = localURL, error == nil else {
                completion(nil)
                return
            }
            
            // Flyt fil til temp directory med korrekt filnavn
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
            
            do {
                try FileManager.default.moveItem(at: localURL, to: fileURL)
                completion(fileURL)
            } catch {
                completion(nil)
            }
        }.resume()
    }
    
    override func serviceExtensionTimeWillExpire() {
        // Hvis download tager for lang tid, send notifikationen uden attachment
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
}
```

### Fase 2: Opdater NotificationService til at sende thumbnail URL

#### 2.1 Tilføj thumbnail URL til notification content

I `NotificationService.swift` og `SmartNotificationService.swift`, når vi sender notifikationer om artikler, skal vi inkludere thumbnail URL:

```swift
func sendArticleNotification(article: Article) {
    let content = UNMutableNotificationContent()
    content.title = "Ny artikel: \(article.name ?? "Ukendt")"
    content.body = article.intro ?? ""
    content.sound = .default
    content.categoryIdentifier = "NEW_ARTICLE"
    content.threadIdentifier = "new_articles"
    
    // Tilføj artikel data til userInfo
    content.userInfo = [
        "type": "new_article",
        "article_id": article.id,
        "thumbnail_url": article.thumbURL?.absoluteString ?? "",
        "cover_url": article.coverURL?.absoluteString ?? ""
    ]
    
    // ... rest of notification setup
}
```

### Fase 3: NotificationContentExtension (Valgfrit - Custom UI)

#### 3.1 Opret NotificationContentExtension Target

1. File → New → Target
2. Vælg "Notification Content Extension"
3. Navn: `AproposMagazineNotificationContent`
4. Bundle Identifier: `com.aproposmagazine.app.AproposMagazineNotificationContent`

#### 3.2 Implementer Custom UI

```swift
// NotificationViewController.swift (i NotificationContentExtension target)
import UIKit
import UserNotifications
import UserNotificationsUI

class NotificationViewController: UIViewController, UNNotificationContentExtension {
    
    @IBOutlet weak var thumbnailImageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var bodyLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        
        // Opdater UI med notifikationsdata
        titleLabel.text = content.title
        bodyLabel.text = content.body
        
        // Hent thumbnail fra attachment
        if let attachment = content.attachments.first,
           attachment.identifier == "article-thumbnail" {
            if attachment.url.startAccessingSecurityScopedResource() {
                if let imageData = try? Data(contentsOf: attachment.url),
                   let image = UIImage(data: imageData) {
                    thumbnailImageView.image = image
                }
                attachment.url.stopAccessingSecurityScopedResource()
            }
        }
    }
}
```

### Fase 4: Info.plist Konfiguration

#### 4.1 NotificationServiceExtension Info.plist

Tilføj til `Info.plist` i NotificationServiceExtension:

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.usernotifications.service</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).NotificationService</string>
</dict>
```

#### 4.2 NotificationContentExtension Info.plist

Tilføj til `Info.plist` i NotificationContentExtension:

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.usernotifications.content</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).NotificationViewController</string>
    <key>NSExtensionAttributes</key>
    <dict>
        <key>UNNotificationExtensionCategory</key>
        <string>NEW_ARTICLE</string>
        <key>UNNotificationExtensionDefaultContentHidden</key>
        <false/>
        <key>UNNotificationExtensionInitialContentSizeRatio</key>
        <real>0.5</real>
    </dict>
</dict>
```

## Test Plan

1. **Test med artikel thumbnail**
   - Send test notifikation med artikel thumbnail URL
   - Verificer at thumbnail vises i notifikationen

2. **Test med manglende thumbnail**
   - Send notifikation uden thumbnail URL
   - Verificer at notifikationen stadig vises korrekt

3. **Test timeout handling**
   - Simuler langsom download
   - Verificer at notifikationen sendes uden attachment hvis download tager for lang tid

4. **Test custom UI**
   - Verificer at custom UI vises korrekt
   - Test med forskellige artikel typer

## Noter

- NotificationServiceExtension har begrænset tid (ca. 30 sekunder) til at downloade og tilføje attachments
- Attachments skal være i et format der understøttes af iOS (JPEG, PNG, GIF, MP4, etc.)
- Attachments har størrelsesbegrænsninger (ca. 10 MB)
- NotificationContentExtension kan kun bruges til lokale notifikationer eller notifikationer der er blevet modificeret af NotificationServiceExtension

## Næste Skridt

1. Opret NotificationServiceExtension target i Xcode
2. Implementer attachment download logik
3. Opdater NotificationService til at inkludere thumbnail URLs
4. Test rich notifications
5. (Valgfrit) Opret NotificationContentExtension for custom UI

