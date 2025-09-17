import SwiftUI

struct PopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        let nav = UINavigationController()
        nav.interactivePopGestureRecognizer?.isEnabled = true
        nav.interactivePopGestureRecognizer?.delegate = nil   // giver mest "native" feel
        nav.navigationBar.isHidden = true                     // vi tegner selv topbar
        return nav
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}
