import SwiftUI
import UIKit

@MainActor
class KeyboardNotificationManager: ObservableObject {
    static let shared = KeyboardNotificationManager()
    
    @Published var keyboardHeight: CGFloat = 0
    @Published var isKeyboardVisible = false
    
    nonisolated private var keyboardWillShowObserver: NSObjectProtocol?
    nonisolated private var keyboardWillHideObserver: NSObjectProtocol?
    nonisolated private var keyboardWillChangeFrameObserver: NSObjectProtocol?
    nonisolated private var keyboardDidShowObserver: NSObjectProtocol?
    nonisolated private var keyboardDidHideObserver: NSObjectProtocol?
    nonisolated private var keyboardDidChangeFrameObserver: NSObjectProtocol?
    
    private var lastNotificationTime: Date = Date()
    private let notificationCooldown: TimeInterval = 0.3
    
    @Published var isWebViewPresent = false
    nonisolated private var webViewDetectionTimer: Timer?
    private var isSignInActive = false
    
    private init() {
        setupKeyboardObservers()
        startWebViewDetection()
    }
    
    deinit {
        removeKeyboardObservers()
        webViewDetectionTimer?.invalidate()
    }
    
    nonisolated private func setupKeyboardObservers() {
        keyboardWillShowObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleKeyboardNotification(notification, type: .willShow)
        }
        
        keyboardWillHideObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleKeyboardNotification(notification, type: .willHide)
        }
        
        keyboardWillChangeFrameObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleKeyboardNotification(notification, type: .willChangeFrame)
        }
        
        keyboardDidShowObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidShowNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleKeyboardNotification(notification, type: .didShow)
        }
        
        keyboardDidHideObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleKeyboardNotification(notification, type: .didHide)
        }
        
        keyboardDidChangeFrameObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidChangeFrameNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleKeyboardNotification(notification, type: .didChangeFrame)
        }
    }
    
    nonisolated private func removeKeyboardObservers() {
        if let observer = keyboardWillShowObserver { NotificationCenter.default.removeObserver(observer); keyboardWillShowObserver = nil }
        if let observer = keyboardWillHideObserver { NotificationCenter.default.removeObserver(observer); keyboardWillHideObserver = nil }
        if let observer = keyboardWillChangeFrameObserver { NotificationCenter.default.removeObserver(observer); keyboardWillChangeFrameObserver = nil }
        if let observer = keyboardDidShowObserver { NotificationCenter.default.removeObserver(observer); keyboardDidShowObserver = nil }
        if let observer = keyboardDidHideObserver { NotificationCenter.default.removeObserver(observer); keyboardDidHideObserver = nil }
        if let observer = keyboardDidChangeFrameObserver { NotificationCenter.default.removeObserver(observer); keyboardDidChangeFrameObserver = nil }
    }
    
    nonisolated private func startWebViewDetection() {
        // Check for web views every 2 seconds
        webViewDetectionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkForWebViews()
        }
    }
    
    private func checkForWebViews() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }
        
        let hasWebView = findWebView(in: window)
        isWebViewPresent = hasWebView
        
        if hasWebView {
            print("[KeyboardNotificationManager] Web view detected")
        }
    }
    
    private func findWebView(in view: UIView) -> Bool {
        // Only detect ASWebAuthenticationSession for Google Sign-In
        if String(describing: type(of: view)).contains("ASWebAuthenticationSession") {
            return true
        }
        
        // Check for Google Sign-In specific accessibility labels
        if let accessibilityLabel = view.accessibilityLabel,
           (accessibilityLabel.lowercased().contains("google") ||
            accessibilityLabel.lowercased().contains("accounts.google.com") ||
            accessibilityLabel.lowercased().contains("sign in")) {
            return true
        }
        
        for subview in view.subviews {
            if findWebView(in: subview) {
                return true
            }
        }
        
        return false
    }
    
    private enum KeyboardNotificationType {
        case willShow, willHide, willChangeFrame, didShow, didHide, didChangeFrame
    }
    
    private func handleKeyboardNotification(_ notification: Notification, type: KeyboardNotificationType) {
        // Only block notifications if sign-in is actively happening
        if isSignInActive {
            print("[KeyboardNotificationManager] Blocking keyboard notification during sign-in: \(notification.name.rawValue)")
            return
        }
        
        // Cooldown to prevent rapid notifications
        let now = Date()
        guard now.timeIntervalSince(lastNotificationTime) > notificationCooldown else {
            return
        }
        lastNotificationTime = now
        
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }
        
        DispatchQueue.main.async {
            switch type {
            case .willShow, .didShow:
                self.keyboardHeight = keyboardFrame.height
                self.isKeyboardVisible = true
            case .willHide, .didHide:
                self.keyboardHeight = 0
                self.isKeyboardVisible = false
            case .willChangeFrame, .didChangeFrame:
                self.keyboardHeight = keyboardFrame.height
            }
        }
    }
    
    func setSignInActive(_ active: Bool) {
        isSignInActive = active
        if active {
            print("[KeyboardNotificationManager] Sign-in active - blocking keyboard notifications")
        } else {
            print("[KeyboardNotificationManager] Sign-in inactive - notifications enabled")
        }
    }
}
