import SwiftUI

@main
struct AproposMagazinev2App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = ArticleViewModel()

    var body: some Scene {
        WindowGroup {
            BootloaderView()
                .environmentObject(viewModel)
                .onOpenURL { url in
                    NavigationCoordinator.shared.handleDeepLink(url)
                }
        }
    }
}
