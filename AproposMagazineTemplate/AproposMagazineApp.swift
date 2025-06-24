import SwiftUI

@main
struct AproposMagazineApp: App {
    @StateObject private var viewModel = ArticleViewModel()

    var body: some Scene {
        WindowGroup {
            ArticleListView()
                .environmentObject(viewModel)
        }
    }
}
