import SwiftUI

@main
struct AproposMagazinev2App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = ArticleViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastForegroundRefresh = Date.distantPast

    var body: some Scene {
        WindowGroup {
            BootloaderView()
                .environmentObject(viewModel)
                .onOpenURL { url in
                    NavigationCoordinator.shared.handleDeepLink(url)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    guard !PodcastPlayerManager.shared.isPlaybackSessionActive else { return }
                    let now = Date()
                    guard now.timeIntervalSince(lastForegroundRefresh) > 30 else { return }
                    lastForegroundRefresh = now
                    viewModel.refreshOnForeground()
                }
        }
    }
}
