import SwiftUI
import GoogleSignIn
import FirebaseAuth

@MainActor
class GoogleSignInService: ObservableObject {
    @Published var isSignedIn = false
    @Published var user: GIDGoogleUser?
    @Published var errorMessage: String?
    @Published var showErrorDialog = false
    
    static let shared = GoogleSignInService()
    
    private init() {
        Task {
            await restorePreviousSignIn()
        }
    }
    
    @MainActor
    private func restorePreviousSignIn() async {
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            self.user = user
            self.isSignedIn = true
            self.errorMessage = nil
            await signInToFirebase(with: user)
        } catch {
            if let currentUser = GIDSignIn.sharedInstance.currentUser {
                self.user = currentUser
                self.isSignedIn = true
                self.errorMessage = nil
            }
        }
    }

    @MainActor
    func signIn() async {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            self.errorMessage = "Kunne ikke finde root view controller"
            self.showErrorDialog = true
            return
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

            await MainActor.run {
                self.user = result.user
                self.isSignedIn = true
                self.errorMessage = nil
                self.showErrorDialog = false
            }

            await signInToFirebase(with: result.user)
            
            if let fcmToken = NotificationService.shared.fcmToken {
                NotificationService.shared.updateFCMTokenOnServer(fcmToken)
            }
        } catch {
            await MainActor.run {
                if let signInError = error as? GIDSignInError {
                    switch signInError.code {
                    case .canceled:
                        self.errorMessage = "Login blev annulleret"
                    case .hasNoAuthInKeychain:
                        self.errorMessage = "Intet tidligere login fundet"
                    default:
                        self.errorMessage = "Login fejlede: \(error.localizedDescription)"
                    }
                } else {
                    self.errorMessage = error.localizedDescription
                }
                self.showErrorDialog = true
            }
        }
    }

    private func signInToFirebase(with user: GIDGoogleUser) async {
        guard let idToken = user.idToken?.tokenString else {
            await MainActor.run {
                self.errorMessage = "Kunne ikke hente ID token"
                self.showErrorDialog = true
            }
            return
        }

        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: user.accessToken.tokenString)

        do {
            let result = try await Auth.auth().signIn(with: credential)
            UserManager.shared.loadUserProfile(for: result.user)
        } catch {
            await MainActor.run {
                self.errorMessage = "Firebase login fejlede: \(error.localizedDescription)"
                self.showErrorDialog = true
            }
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        do {
            try Auth.auth().signOut()
        } catch {
            print("Fejl ved logout fra Firebase: \(error)")
        }

        self.user = nil
        self.isSignedIn = false
        self.errorMessage = nil
        self.showErrorDialog = false
        UserManager.shared.currentUser = nil
    }
    
    func dismissErrorDialog() {
        self.showErrorDialog = false
        self.errorMessage = nil
    }
}
