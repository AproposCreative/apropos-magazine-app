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
                    // Refresh the feed whenever the app returns to the foreground,
                    // throttled so a quick app-switch doesn't trigger redundant
                    // fetches. SwiftUI's onAppear does not fire on warm resume, so
                    // without this the list would stay stale until pull-to-refresh.
                    let now = Date()
                    guard now.timeIntervalSince(lastForegroundRefresh) > 30 else { return }
                    lastForegroundRefresh = now
                    viewModel.refreshOnForeground()
                }
        }
    }
}
