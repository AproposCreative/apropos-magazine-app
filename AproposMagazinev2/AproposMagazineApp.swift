import Combine
import SwiftUI

@main
struct AproposMagazinev2App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = ArticleViewModel(languagePreferences: PreferencesManager.shared)
    @ObservedObject private var incomingLinks = IncomingLinkRuntime.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastForegroundRefresh = Date.distantPast
    private let isRunningUnitTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    var body: some Scene {
        WindowGroup {
            if isRunningUnitTests {
                Color.clear
            } else {
                launchContent
                    .environment(\.locale, interfaceLocale)
            }
        }
    }

    private var interfaceLocale: Locale {
        #if DEBUG && targetEnvironment(simulator)
        // Presentation-only gallery coverage. Never persist a language choice
        // or let a smoke argument change the live application's preference.
        if LocalSmokeMode.isEnabled,
           ProcessInfo.processInfo.arguments.contains("-AproposInterfaceEnglishSmoke") {
            return AppLocalization.locale(for: .english)
        }
        #endif
        return AppLocalization.locale(for: viewModel.articleLanguage)
    }

    @ViewBuilder private var launchContent: some View {
        #if DEBUG && targetEnvironment(simulator)
        if LocalSmokeMode.isEnabled {
            if ProcessInfo.processInfo.arguments.contains("-AproposAccountGateSmoke") {
                LocalAccountGateSmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposFigmaReferenceSmoke") {
                LocalFigmaReferenceSmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposContentLanguageSmoke") {
                LocalContentLanguageSmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposArticleBackSmoke") {
                LocalArticleBackSmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposNotificationAttentionSmoke") {
                LocalNotificationAttentionSmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposNotificationInboxSmoke") {
                LocalNotificationInboxSmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposIntroductionSmoke") {
                LocalIntroductionSmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposHomeSmoke") {
                LocalHomeSmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposReaderAccountSmoke") {
                LocalReaderAccountSmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposAudioAssetSmoke") {
                LocalAudioAssetSmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposIncomingLinkSmoke") {
                LocalIncomingLinkSmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposFavoriteButtonSmoke") {
                LocalFavoriteButtonSmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposOfflineImageSmoke") {
                LocalOfflineImageSmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposOfflineBodySmoke") {
                LocalOfflineBodySmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposOfflineSettingsSmoke") {
                LocalOfflineSettingsSmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposArticleTagsSmoke") {
                LocalArticleTagsSmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposArticleHeaderTextSmoke") {
                LocalArticleHeaderTextSmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposFavoritesSmoke") {
                LocalFavoritesSmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposProfileSmoke") {
                LocalProfileSmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposHistorySmoke") {
                LocalReadingHistorySmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposProgressSmoke") {
                LocalPodcastProgressSmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposSupportSmoke") {
                LocalSupportSmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposPrivacySmoke") {
                LocalPrivacySmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposReaderMotionSmoke") {
                LocalReaderMotionSmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposReaderResumeSmoke") {
                LocalReaderResumeSmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposArticleMediaSmoke") {
                LocalArticleMediaSmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposArticleLoadingSmoke") {
                LocalArticleLoadingSmokeView()
            } else if ProcessInfo.processInfo.arguments.contains("-AproposReaderSmoke") {
                LocalReaderAvailabilitySmokeView()
            } else {
                if ProcessInfo.processInfo.arguments.contains("-AproposGoogleReauthenticationSmoke") {
                    LocalGoogleReauthenticationSmokeView()
                } else if ProcessInfo.processInfo.arguments.contains("-AproposAppleReauthenticationSmoke") {
                    LocalAppleReauthenticationSmokeView()
                } else if ProcessInfo.processInfo.arguments.contains("-AproposAccountRecoverySmoke") {
                    LocalAccountRecoverySmokeView()
                } else if ProcessInfo.processInfo.arguments.contains("-AproposEmailReauthenticationSmoke") {
                    LocalEmailReauthenticationSmokeView()
                } else {
                    LocalAccountSmokeView()
                }
            }
        } else {
            normalContent
        }
        #else
        normalContent
        #endif
    }

    private var normalContent: some View {
        BootloaderView()
            .environmentObject(viewModel)
            .incomingLinkFeedback(message: incomingLinks.message, messageID: incomingLinks.messageID,
                                  dismiss: { incomingLinks.dismissMessage(id: $0) })
            .onOpenURL { url in
                _ = IncomingLinkEntryRuntime.entry.openURL(url)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                _ = IncomingLinkEntryRuntime.entry.continueActivity(type: activity.activityType, webpageURL: activity.webpageURL)
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                NotificationInboxRuntime.didBecomeActive()
                ReaderPreferencesService.shared.refreshAfterInterruption()
                viewModel.refreshFavoritesAfterInterruption()
                viewModel.homeSceneBecameActive()
                OfflineManager.shared.recoverSavedAudioDownloads()
                viewModel.refreshSavedOfflineAfterInterruption()
                guard !PodcastPlayerManager.shared.isPlaybackSessionActive else { return }
                let now = Date()
                guard now.timeIntervalSince(lastForegroundRefresh) > 30 else { return }
                lastForegroundRefresh = now
                viewModel.refreshOnForeground()
            }
            .onReceive(OfflineManager.shared.$isOnline.removeDuplicates().dropFirst()) { isOnline in
                guard isOnline else { return }
                OfflineManager.shared.performAfterOnlinePublication(isActive: { scenePhase == .active }) {
                    ReaderPreferencesService.shared.refreshAfterInterruption()
                    viewModel.refreshFavoritesAfterInterruption()
                    OfflineManager.shared.recoverSavedAudioDownloads()
                    viewModel.refreshSavedOfflineAfterInterruption()
                }
            }
    }
}
