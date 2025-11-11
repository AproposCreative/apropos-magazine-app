# AproposMagazineNotificationService

Notification Service Extension for Rich Notifications with article thumbnails.

## Setup Instructions

### 1. Opret Target i Xcode

1. Åbn Xcode
2. File → New → Target
3. Vælg "Notification Service Extension"
4. Navn: `AproposMagazineNotificationService`
5. Bundle Identifier: `com.aproposmagazine.app.AproposMagazineNotificationService`
6. Language: Swift

### 2. Erstat Default Filer

1. Erstat `NotificationService.swift` med filen fra denne mappe
2. Erstat `Info.plist` med filen fra denne mappe (eller opdater eksisterende)

### 3. Konfigurer Target

1. Vælg NotificationServiceExtension target
2. Gå til "Signing & Capabilities"
3. Vælg samme Team som hovedappen
4. Sørg for at Bundle Identifier matcher: `com.aproposmagazine.app.AproposMagazineNotificationService`

### 4. Test

1. Build og run appen
2. Send en test notifikation med `NotificationService.shared.sendArticleNotification(article:)`
3. Verificer at thumbnail vises i notifikationen

## Hvordan det virker

1. Appen sender en notifikation med artikel data i `userInfo`
2. NotificationServiceExtension modtager notifikationen
3. Extension downloader artikel thumbnail fra URL
4. Extension tilføjer thumbnail som `UNNotificationAttachment`
5. Notifikationen vises med thumbnail

## Noter

- Extension har begrænset tid (ca. 30 sekunder) til at downloade og tilføje attachments
- Hvis download fejler, sendes notifikationen uden attachment
- Attachments skal være i et format der understøttes af iOS (JPEG, PNG, GIF, MP4, etc.)

