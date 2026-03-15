import SwiftUI
import Foundation
import OSLog

enum AppRoute: Hashable {
    case home
    case search
    case cinemas
    case watchlist
    case profile
    case movieDetail(Movie)
    case cinemaDetail(Cinema)
}

enum Tab: String, CaseIterable, Identifiable, Codable {
    case home = "Film"
    case search = "Søg"
    case cinemas = "Biografer"
    case watchlist = "Watchlist"
    case profile = "Profil"
    
    var id: String { self.rawValue }
    
    var systemImage: String {
        switch self {
        case .home: return "film.fill"
        case .search: return "magnifyingglass"
        case .cinemas: return "building.2.fill"
        case .watchlist: return "heart.fill"
        case .profile: return "person.fill"
        }
    }
}

@MainActor
class NavigationCoordinator: ObservableObject {
    static let shared = NavigationCoordinator()
    
    @Published var selectedTab: Tab = .home
    
    @Published var homePath = NavigationPath()
    @Published var searchPath = NavigationPath()
    @Published var cinemasPath = NavigationPath()
    @Published var watchlistPath = NavigationPath()
    @Published var profilePath = NavigationPath()
    
    @Published var pendingDeepLink: URL?
    
    private let logger = Logger(subsystem: "dk.gobio.app", category: "NavigationCoordinator")
    
    private init() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("OpenMovieFromNotification"),
            object: nil,
            queue: .main
        ) { [unowned self] notification in
            if let movieId = notification.userInfo?["movieId"] as? Int {
                Task { @MainActor in
                    self.selectedTab = .home
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    self.logger.info("Navigerer til film fra notifikation: \(movieId)")
                }
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func path(for tab: Tab) -> Binding<NavigationPath> {
        switch tab {
        case .home: return Binding(get: { self.homePath }, set: { self.homePath = $0 })
        case .search: return Binding(get: { self.searchPath }, set: { self.searchPath = $0 })
        case .cinemas: return Binding(get: { self.cinemasPath }, set: { self.cinemasPath = $0 })
        case .watchlist: return Binding(get: { self.watchlistPath }, set: { self.watchlistPath = $0 })
        case .profile: return Binding(get: { self.profilePath }, set: { self.profilePath = $0 })
        }
    }
    
    func navigateToTab(_ tab: Tab) {
        selectedTab = tab
    }
    
    func navigateToMovie(_ movie: Movie, in tab: Tab) {
        switch tab {
        case .home: homePath.append(movie)
        case .search: searchPath.append(movie)
        case .cinemas: cinemasPath.append(movie)
        case .watchlist: watchlistPath.append(movie)
        case .profile: profilePath.append(movie)
        }
    }
    
    func goBack(in tab: Tab) {
        switch tab {
        case .home: if !homePath.isEmpty { homePath.removeLast() }
        case .search: if !searchPath.isEmpty { searchPath.removeLast() }
        case .cinemas: if !cinemasPath.isEmpty { cinemasPath.removeLast() }
        case .watchlist: if !watchlistPath.isEmpty { watchlistPath.removeLast() }
        case .profile: if !profilePath.isEmpty { profilePath.removeLast() }
        }
    }
    
    func goToRoot(in tab: Tab) {
        switch tab {
        case .home: homePath = NavigationPath()
        case .search: searchPath = NavigationPath()
        case .cinemas: cinemasPath = NavigationPath()
        case .watchlist: watchlistPath = NavigationPath()
        case .profile: profilePath = NavigationPath()
        }
    }
    
    func handleDeepLink(_ url: URL) {
        logger.info("Håndterer deep link: \(url.absoluteString, privacy: .public)")
        
        guard url.scheme == "gobio" || url.host == "gobio.dk" else { return }
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        if pathComponents.count >= 2 {
            let type = pathComponents[0]
            let identifier = pathComponents[1]
            
            switch type {
            case "movie":
                if let movieId = Int(identifier) {
                    logger.info("Deep link til film: \(movieId)")
                }
            case "cinema":
                logger.info("Deep link til biograf: \(identifier, privacy: .public)")
            default:
                logger.warning("Ukendt deep link type: \(type, privacy: .public)")
            }
        }
        
        pendingDeepLink = url
    }
}

private struct NavigationCoordinatorKey: EnvironmentKey {
    @MainActor static var defaultValue: NavigationCoordinator {
        NavigationCoordinator.shared
    }
}

extension EnvironmentValues {
    var navigationCoordinator: NavigationCoordinator {
        get { self[NavigationCoordinatorKey.self] }
        set { self[NavigationCoordinatorKey.self] = newValue }
    }
}
