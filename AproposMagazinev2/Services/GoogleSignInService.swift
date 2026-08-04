import SwiftUI
import GoogleSignIn
import FirebaseAuth
import AuthenticationServices

@MainActor
class GoogleSignInService: ObservableObject {
    @Published var isSignedIn = false
    @Published var user: GIDGoogleUser?
    @Published var errorMessage: String?
    @Published var showErrorDialog = false
    
    static let shared = GoogleSignInService()
    
    private init() {
        // Check if user is already signed in and restore previous session
        Task {
            await restorePreviousSignIn()
        }
    }
    
    @MainActor
    private func restorePreviousSignIn() async {
        do {
            // Try to restore previous sign-in
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            self.user = user
            self.isSignedIn = true
            self.errorMessage = nil
            await signInToFirebase(with: user)
        } catch {
            // Don't treat this as a critical error - it's normal for first-time users
            if let currentUser = GIDSignIn.sharedInstance.currentUser {
                self.user = currentUser
                self.isSignedIn = true
                self.errorMessage = nil
            }
        }
    }

    @MainActor
    func signIn() async {
        guard let presenter = topViewController() else {
            self.errorMessage = "Could not find root view controller"
            self.showErrorDialog = true
            return
        }
        
        do {
            // Present from the topmost VC so a login sheet does not block/loop Google auth.
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)

            self.user = result.user
            self.isSignedIn = true
            self.errorMessage = nil
            self.showErrorDialog = false

            // Sign in to Firebase with Google credentials
            await signInToFirebase(with: result.user)
            
            // Update FCM token on server after successful login
            if let fcmToken = NotificationService.shared.fcmToken {
                NotificationService.shared.updateFCMTokenOnServer(fcmToken)
            }
        } catch {
            // Handle specific error cases
            if let signInError = error as? GIDSignInError {
                switch signInError.code {
                case .canceled:
                    self.errorMessage = "Sign-in was canceled"
                case .hasNoAuthInKeychain:
                    self.errorMessage = "No previous sign-in found"
                default:
                    self.errorMessage = "Sign-in failed: \(error.localizedDescription)"
                }
            } else {
                self.errorMessage = error.localizedDescription
            }
            self.showErrorDialog = true
        }
    }

    /// Walk the presented-view hierarchy so Google Sign-In can appear above sheets.
    @MainActor
    private func topViewController(from controller: UIViewController? = nil) -> UIViewController? {
        let root = controller ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController

        if let nav = root as? UINavigationController {
            return topViewController(from: nav.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(from: presented)
        }
        return root
    }

    private func signInToFirebase(with user: GIDGoogleUser) async {
        guard let idToken = user.idToken?.tokenString else {
            await MainActor.run {
                self.errorMessage = "Failed to get ID token"
                self.showErrorDialog = true
            }
            return
        }

        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: user.accessToken.tokenString)

        do {
            let result = try await Auth.auth().signIn(with: credential)

            // Update UserManager with the signed-in user
            UserManager.shared.loadUserProfile(for: result.user)
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Firebase sign-in failed: \(error.localizedDescription)"
                self.showErrorDialog = true
            }
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        do {
            try Auth.auth().signOut()
        } catch {
        }

        self.user = nil
        self.isSignedIn = false
        self.errorMessage = nil
        self.showErrorDialog = false
        
        // Clear UserManager
        UserManager.shared.currentUser = nil
    }
    
    func dismissErrorDialog() {
        self.showErrorDialog = false
        self.errorMessage = nil
    }
    
    func clearError() {
        self.errorMessage = nil
        self.showErrorDialog = false
    }
}
