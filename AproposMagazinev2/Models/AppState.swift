import Foundation

@MainActor
final class AppState: ObservableObject {
    enum Tab: Hashable { 
        case home, search, categories, saved, profile 
    }
    
    @Published var selectedTab: Tab = .home
    @Published var homeScrollToTopToggle = false
    
    init() {
        // Initialize with default state
    }
}
