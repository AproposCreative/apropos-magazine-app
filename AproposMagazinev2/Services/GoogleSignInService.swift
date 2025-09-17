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
            print("[GoogleSignInService] Successfully restored previous sign-in for: \(user.profile?.email ?? "Unknown")")
        } catch {
            print("[GoogleSignInService] Error restoring previous sign-in: \(error)")
            // Don't treat this as a critical error - it's normal for first-time users
            if let currentUser = GIDSignIn.sharedInstance.currentUser {
                self.user = currentUser
                self.isSignedIn = true
                self.errorMessage = nil
                print("[GoogleSignInService] Fallback to current user: \(currentUser.profile?.email ?? "Unknown")")
            } else {
                print("[GoogleSignInService] No previous sign-in found")
                // This is normal for first-time users, don't set error state
            }
        }
    }

    @MainActor
    func signIn() async {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            self.errorMessage = "Could not find root view controller"
            self.showErrorDialog = true
            return
        }
        
        print("[GoogleSignInService] Starting Google Sign-In process")

        do {
            // Use the new sign-in method that uses ASWebAuthenticationSession
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

            await MainActor.run {
                self.user = result.user
                self.isSignedIn = true
                self.errorMessage = nil
                self.showErrorDialog = false
            }

            // Sign in to Firebase with Google credentials
            await signInToFirebase(with: result.user)
            print("[GoogleSignInService] Sign-in completed successfully")

        } catch {
            await MainActor.run {
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
            print("[GoogleSignInService] Sign-in failed: \(error.localizedDescription)")
        }
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
            print("Successfully signed in to Firebase with user: \(result.user.email ?? "Unknown")")
            
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
            print("Error signing out from Firebase: \(error)")
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
