# Changelog

## [1.4] - 2026-06-04

- **Bedre artikel-læsning**
  - Afsnit har luft imellem sig, intro-tekst med højere line height, og inline-billeder loader korrekt (WebP + optimerede CMS-størrelser).
- **Billedkreditter**
  - Ophavsret vises som centreret pille under billeder.
- **Log ind i Indstillinger**
  - Google Sign-In med default avatar og "Log ind eller opret en bruger".
- **Forsiden edge-to-edge**
  - Hero-billedet går helt op til toppen uden gap.
- **Notifikations-knap fix**
  - Synlig primær knap i onboarding-sheet i lys og mørk tilstand.

## [1.2] - 2026-05-29

- **Nye podcasts uden app-update**
  - Nye Apropos Podcast-afsnit dukker op i appen automatisk uden ny App Store-version.
- **Besked når ny podcast udkommer**
  - Push-notifikation når et nyt podcast-afsnit er klar.
- **Forbedret podcast-afspiller**
  - Kategori, værter, systemlydstyrke og swipe ned for at lukke.
- **Notifikationer ved første åbning**
  - Velkomst til artikel- og podcast-notifikationer.
- **Hjem virker overalt**
  - Hjem-knappen bringer dig til forsiden fra enhver artikel.
- **Hurtigere artikler**
  - Hurtigere åbning af artikler og mere responsiv forside.

## [Unreleased] - 2025-01-XX

### 🔔 Notification System Improvements

#### Backend (Cloud Run / Firebase Functions)
- **Fixed duplicate notifications for republished articles**
  - Implemented Firestore-based tracking system (`notified_articles` collection)
  - Articles are now tracked when first published, preventing duplicate notifications on republish
  - Added comprehensive logging for debugging notification flow
  - Added validation to block notifications if `article_id` is empty
  - Changed error handling: if Firestore check fails, notification is blocked (safer than sending duplicates)

- **Fixed missing article_id in notification payload**
  - Corrected Webflow webhook payload parsing to extract `article_id` from `webhookData.payload.items[0].id`
  - Added `thumbnail_url` and `cover_url` to notification payload for rich notifications
  - Added `mutable-content: 1` flag to APNS payload to enable Notification Service Extension

- **Improved webhook trigger filtering**
  - Only sends notifications for `collection_item_published` or `publish` triggers
  - Ignores `collection_item_changed` and `collection_item_created` triggers

#### iOS App
- **Notification Service Extension**
  - Implemented duplicate notification check using cached articles
  - If article exists in cache (App Group or standard UserDefaults), notification is blocked
  - Added fallback to find article by name if `article_id` is missing
  - Added rich notification support with thumbnail images
  - Fixed App Groups capability configuration for data sharing between app and extension

- **AppDelegate notification handling**
  - Added duplicate check in `willPresent` for foreground notifications
  - Simplified logic: if article exists in cache, it's considered already published
  - Improved logging for debugging

- **Cache Manager**
  - Updated to save simplified article data to App Group UserDefaults
  - Enables Notification Service Extension to access cached articles for duplicate checks

### 🎨 What's New Feature

- **Fixed What's New display timing**
  - Consolidated duplicate `.onAppear` modifiers
  - Added 0.5 second delay to ensure ContentView is fully visible before showing sheet
  - Improved logging for debugging
  - Updated to mark all entries as seen when dismissed (prevents re-showing)

- **What's New Manager**
  - Automatically shows latest version if not seen before
  - Compares versions semantically (e.g., 2.3.0 > 2.2.0)
  - Supports multiple entries in `whatsnew.json`
  - Stores last seen version in UserDefaults

### 🧹 Code Cleanup

- **Removed verbose logging**
  - Reduced console spam from various services
  - Kept essential logging for debugging
  - Removed unnecessary print statements

- **Removed guide files**
  - Deleted temporary guide files (`FIX_INDEX_JS.txt`, `QUICK_FIX_GUIDE.md`, `IMPLEMENTATION_GUIDE.md`)
  - Cleaned up project structure

### 🐛 Bug Fixes

- **Fixed NavigationCoordinator deallocation**
  - Converted to singleton pattern to ensure persistent instance
  - Fixed `nil` NavigationCoordinator in notification observers

- **Fixed Firestore persistence configuration**
  - Moved `configurePersistenceIfNeeded()` to `AppDelegate.didFinishLaunchingWithOptions()`
  - Added static flag to prevent multiple configurations
  - Fixed `FIRIllegalStateException` crash

- **Fixed console spam**
  - Removed excessive logging from SwipeBack, SplashView, and other components
  - Cleaned up debug messages

### 📝 Documentation

- Added comprehensive changelog documenting all recent changes
- Improved code comments for notification system
- Added logging for debugging What's New feature

---

## Technical Details

### Notification Flow

1. **Webflow publishes article** → Webhook sent to Cloud Run service
2. **Backend checks Firestore** → If article exists in `notified_articles`, block notification
3. **If new article** → Mark as notified in Firestore, send FCM notification
4. **iOS receives notification** → Notification Service Extension checks cache
5. **If article in cache** → Block notification (already published)
6. **If new article** → Show notification with thumbnail

### What's New Flow

1. **App launches** → ContentView appears
2. **After 0.5 second delay** → Check if What's New should be shown
3. **Compare current version** with last seen version
4. **If newer version** → Show What's New sheet
5. **When dismissed** → Mark all entries as seen

### Files Modified

#### Backend
- `functions/index.js` - Webflow webhook handler with Firestore tracking

#### iOS App
- `AppDelegate.swift` - Notification handling and duplicate checks
- `AproposMagazineNotificationService/NotificationService.swift` - Notification Service Extension
- `Services/CacheManager.swift` - App Group cache support
- `ContentView.swift` - What's New display logic
- `Managers/WhatsNewManager.swift` - What's New version management
- `Models/NavigationCoordinator.swift` - Singleton pattern implementation
- Various services - Reduced verbose logging

---

## Migration Notes

### For Developers

1. **Backend Deployment**: Deploy `functions/index.js` with Firebase Functions
2. **Firestore Setup**: Ensure `notified_articles` collection has proper permissions
3. **App Groups**: Verify both app and extension have `group.com.aproposmagazine.app` capability
4. **What's New**: Update `Resources/WhatsNew/whatsnew.json` with new version entries

### For Users

- No action required
- What's New will automatically appear for new app versions
- Notifications will only appear for truly new articles (not republished ones)

