import SwiftUI
import FirebaseCore

@main
struct AproposMagazinev2App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Configure Firebase as early as possible
        print("🔥 AproposMagazinev2App: Starting Firebase configuration...")
        FirebaseApp.configure()
        print("🔥 AproposMagazinev2App: Firebase configuration completed")
    }
    
    var body: some Scene {
        WindowGroup {
            BootloaderView()
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
