import FirebaseCore
import OSLog
import SwiftUI

@main
struct AproposMagazinev2App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private static let logger = Logger(subsystem: "com.aproposmagazine.app", category: "AproposMagazinev2App")
    
    init() {
        // Configure Firebase as early as possible
        Self.logger.info("Starter Firebase-konfiguration.")
        FirebaseApp.configure()
        Self.logger.info("Firebase-konfiguration fuldført.")
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
