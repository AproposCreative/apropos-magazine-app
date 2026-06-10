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

struct MinimalDataView: View {
    @State private var rawData: String = "Henter data..."
    private let fetcher = DirectFetcher()

    var body: some View {
        ScrollView {
            VStack {
                Text(rawData)
                    .padding()
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            fetcher.fetchData { dataString in
                self.rawData = dataString
            }
        }
    }
}
