import SwiftUI
import UIKit

extension Notification.Name {
    static let scrollHomeToTop = Notification.Name("ScrollHomeToTop")
}

struct TabBarSelectionHandler: UIViewControllerRepresentable {
    let homeTabIndex: Int
    let onHomeTabSelected: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isHidden = true
        controller.view.frame = .zero
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.homeTabIndex = homeTabIndex
        context.coordinator.onHomeTabSelected = onHomeTabSelected

        DispatchQueue.main.async {
            let tabBarController = uiViewController.tabBarController ?? Self.findTabBarController()
            guard let tabBarController else { return }
            tabBarController.delegate = context.coordinator
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(homeTabIndex: homeTabIndex, onHomeTabSelected: onHomeTabSelected)
    }

    private static func findTabBarController() -> UITabBarController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController?
            .tabBarController
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        var homeTabIndex: Int
        var onHomeTabSelected: () -> Void

        init(homeTabIndex: Int, onHomeTabSelected: @escaping () -> Void) {
            self.homeTabIndex = homeTabIndex
            self.onHomeTabSelected = onHomeTabSelected
        }

        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            guard let index = tabBarController.viewControllers?.firstIndex(of: viewController),
                  index == homeTabIndex else {
                return true
            }

            Task { @MainActor in
                onHomeTabSelected()
            }
            return true
        }
    }
}
