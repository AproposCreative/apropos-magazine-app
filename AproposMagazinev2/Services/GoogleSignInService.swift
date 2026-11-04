import Combine
import SwiftUI
import GoogleSignIn
import FirebaseAuth
import AuthenticationServices

@MainActor
class GoogleSignInService: ObservableObject {
    struct ReauthenticationIdentity: Equatable, Sendable {
        let idToken: String
        let accessToken: String
        let userID: String
    }
    typealias ReauthenticationProvider = @MainActor (
        @escaping @MainActor () -> Bool,
        @escaping @Sendable (ReauthenticationIdentity?, Error?) -> Void
    ) throws -> Void
    enum ReauthenticationFailure: Error, Equatable { case alreadyWorking, invalidIdentity }
    @MainActor private final class ReauthenticationFlight {
        let action: ReaderAccountDeletionCoordinator.ActionTicket
        let expectedSubject: String
        let isCurrent: @MainActor () -> Bool
        var denied = false
        init(action: ReaderAccountDeletionCoordinator.ActionTicket, expectedSubject: String,
             isCurrent: @escaping @MainActor () -> Bool) {
            self.action = action; self.expectedSubject = expectedSubject; self.isCurrent = isCurrent
        }
    }
    private let reauthenticationProvider: ReauthenticationProvider
    private var reauthenticationFlight: ReauthenticationFlight?
    var isReauthenticating: Bool { reauthenticationFlight != nil }
    // Commit before synchronous observers can cancel/capture a different intent.
    nonisolated let objectWillChange = ObservableObjectPublisher()
    var isSignedIn = false { didSet { objectWillChange.send() } }
    var user: GIDGoogleUser? { didSet { objectWillChange.send() } }
    var errorMessage: String? { didSet { objectWillChange.send() } }
    var showErrorDialog = false { didSet { objectWillChange.send() } }
    
    static let shared = GoogleSignInService()
    
    // Firebase Auth restores the account. Restoring a separate Google session
    // here could replace an email account or race an explicit logout.
    private init() {
        reauthenticationProvider = { admitted, completion in
            guard admitted(), let presenter = GoogleSignInService.shared.topViewController(), admitted() else { throw CancellationError() }
            let provider = GIDSignIn.sharedInstance
            guard admitted() else { throw CancellationError() }
            // No restore/signOut/disconnect: cancellation revokes the caller's
            // intent while this actual interactive callback retains its slot.
            provider.signIn(withPresenting: presenter) { result, error in
                let value = result.flatMap { result -> ReauthenticationIdentity? in
                    guard let token = result.user.idToken?.tokenString, let subject = result.user.userID else { return nil }
                    return ReauthenticationIdentity(idToken: token, accessToken: result.user.accessToken.tokenString, userID: subject)
                }
                completion(value, error)
            }
        }
    }

    /// Injection constructs no provider, Firebase service, presenter or session.
    init(reauthenticationProvider: @escaping ReauthenticationProvider) {
        self.reauthenticationProvider = reauthenticationProvider
    }

    /// Called inside the existing shared AuthOperationCoordinator reservation.
    /// Only provider identity is returned; no Firebase signIn or login fields are changed.
    func reauthenticate(action: ReaderAccountDeletionCoordinator.ActionTicket, expectedGoogleUserID: String,
                        isCurrent: @escaping @MainActor () -> Bool) async throws -> ReauthenticationIdentity {
        try Task.checkCancellation()
        guard reauthenticationFlight == nil else { throw ReauthenticationFailure.alreadyWorking }
        guard action.context.userID == action.request.expectedUID, !expectedGoogleUserID.isEmpty,
              expectedGoogleUserID.utf8.count <= 1_024,
              !expectedGoogleUserID.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            throw ReauthenticationFailure.invalidIdentity
        }
        let original = ReauthenticationFlight(action: action, expectedSubject: expectedGoogleUserID, isCurrent: isCurrent)
        reauthenticationFlight = original // Reserve before observable or injected hooks.
        defer {
            if reauthenticationFlight === original { reauthenticationFlight = nil; objectWillChange.send() }
        }
        objectWillChange.send()
        guard admits(original), !Task.isCancelled else { throw CancellationError() }
        let value: ReauthenticationIdentity = try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                guard admits(original), !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                let first = GoogleReauthenticationFirstReply()
                let completion: @Sendable (ReauthenticationIdentity?, Error?) -> Void = { [self] value, error in
                    guard first.take() else { return }
                    let result = ReaderReauthenticationCallback.result(value, error: error)
                    Task { @MainActor in
                        guard self.admits(original) else { continuation.resume(throwing: CancellationError()); return }
                        switch result {
                        case .failure(let error):
                            if let cancellation = error as? GIDSignInError, cancellation.code == .canceled {
                                continuation.resume(throwing: CancellationError())
                            } else { continuation.resume(throwing: error) }
                        case .success(let identity):
                            guard identity.userID == original.expectedSubject,
                                  Self.validReauthenticationToken(identity.idToken), Self.validReauthenticationToken(identity.accessToken) else {
                                continuation.resume(throwing: ReauthenticationFailure.invalidIdentity); return
                            }
                            guard self.admits(original) else { continuation.resume(throwing: CancellationError()); return }
                            continuation.resume(returning: identity)
                        }
                    }
                }
                do {
                    try reauthenticationProvider({ [weak self, weak original] in
                        guard let self, let original else { return false }; return self.admits(original)
                    }, completion)
                } catch { completion(nil, error) } // Throwing provider setup must not have started a physical request.
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in self?.cancelReauthentication(action: action) }
        })
        guard admits(original), !Task.isCancelled else { throw CancellationError() }
        return value
    }

    func cancelReauthentication(action: ReaderAccountDeletionCoordinator.ActionTicket) {
        guard let original = reauthenticationFlight, original.action == action else { return }
        original.denied = true // No public Google API can cancel this physical flow safely.
    }
    private func admits(_ original: ReauthenticationFlight) -> Bool {
        guard reauthenticationFlight === original, !original.denied else { return false }
        let allowed = original.isCurrent()
        guard allowed, reauthenticationFlight === original, !original.denied else { original.denied = true; return false }
        return true
    }
    nonisolated private static func validReauthenticationToken(_ value: String) -> Bool {
        (1...16_384).contains(value.utf8.count) && value.utf8.allSatisfy { (33...126).contains($0) }
    }

    /// Captured by the actual button before it creates a Task.
    func captureSignIn(newsletterOptIn: Bool = false) -> AuthOperationCoordinator.Ticket? {
        do { return try AuthService.shared.captureLogin(.google, newsletterOptIn: newsletterOptIn) }
        catch is CancellationError { return nil }
        catch {
            errorMessage = (error as? AuthOperationCoordinator.Failure)?.message ?? "Google-login kunne ikke klargøres. Prøv igen."
            showErrorDialog = true
            return nil
        }
    }

    func cancel(_ ticket: AuthOperationCoordinator.Ticket) { AuthService.shared.cancelLogin(ticket) }

    func signIn(ticket: AuthOperationCoordinator.Ticket) async {
        let canonical = AuthService.shared
        guard ticket.kind == .google else { canonical.cancelLogin(ticket); return }
        guard let presenter = topViewController() else {
            if canonical.loginFeedbackIsCurrent(ticket) {
                errorMessage = "Kunne ikke åbne Google-login. Prøv igen."
                if canonical.loginFeedbackIsCurrent(ticket) { showErrorDialog = true }
            }
            canonical.cancelLogin(ticket)
            return
        }
        do {
            let result = try await canonical.loginProvider(ticket) {
                try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            }
            guard let idToken = result.user.idToken?.tokenString else {
                if canonical.loginFeedbackIsCurrent(ticket) {
                    errorMessage = "Google kunne ikke bekræfte login. Prøv igen."
                    if canonical.loginFeedbackIsCurrent(ticket) { showErrorDialog = true }
                }
                canonical.cancelLogin(ticket)
                return
            }
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
            guard let session = try await canonical.signIn(credential: credential, ticket: ticket),
                  canonical.loginFeedbackIsCurrent(ticket), session.uid == canonical.session?.uid else { return }
            user = result.user
            guard canonical.loginFeedbackIsCurrent(ticket) else { return }
            isSignedIn = true
            guard canonical.loginFeedbackIsCurrent(ticket) else { return }
            errorMessage = nil
            guard canonical.loginFeedbackIsCurrent(ticket) else { return }
            showErrorDialog = false
        } catch is CancellationError { }
        catch {
            guard canonical.loginFeedbackIsCurrent(ticket) else { return }
            if let error = error as? GIDSignInError, error.code == .canceled {
                errorMessage = nil
                if canonical.loginFeedbackIsCurrent(ticket) { showErrorDialog = false }
                return
            }
            errorMessage = (error as? AuthOperationCoordinator.Failure)?.message ?? AccountErrorMessage.forError(error)
            guard canonical.loginFeedbackIsCurrent(ticket) else { return }
            showErrorDialog = true
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

    @discardableResult
    func signOut() -> Bool {
        do { try AuthService.shared.signOut() }
        catch {
            errorMessage = (error as? AuthOperationCoordinator.Failure)?.message ?? "Udlogningen kunne ikke bekræftes. Prøv igen."
            showErrorDialog = true
            return false
        }
        GIDSignIn.sharedInstance.signOut()
        self.user = nil
        self.isSignedIn = false
        self.errorMessage = nil
        self.showErrorDialog = false
        UserManager.shared.clearIfConfirmedGuest()
        return true
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

/// Reserve the FIRST physical callback before crossing onto the main actor.
private final class GoogleReauthenticationFirstReply: @unchecked Sendable {
    private let lock = NSLock()
    private var received = false
    func take() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !received else { return false }; received = true; return true
    }
}
