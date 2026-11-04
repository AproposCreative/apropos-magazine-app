import SwiftUI
import GoogleSignIn

struct GoogleSignInButton: View {
    var onBusyChanged: (Bool) -> Void = { _ in }
    var lifetime: AccountLoginLifetime? = nil
    var newsletterOptIn: () -> Bool = { false }
    var activation: UUID? = nil
    var activationIsCurrent: () -> Bool = { true }
    var onLoginStarted: (UUID) -> Void = { _ in }
    var onAuthenticated: (ReaderLoginResult) -> Void = { _ in }
    var onLoginFinished: (UUID) -> Void = { _ in }
    var introductionStyle = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var signInService: GoogleSignInService
    private var reauthentication: (prompt: ReaderGoogleReauthenticationPrompt,
                                  presentation: ReaderGoogleReauthenticationPrompt.Presentation)?
    @State private var isLoading = false
    @State private var operation: AuthOperationCoordinator.Ticket?
    @State private var consumedActivation: UUID?

    init(onBusyChanged: @escaping (Bool) -> Void = { _ in }, lifetime: AccountLoginLifetime? = nil,
         newsletterOptIn: @escaping () -> Bool = { false }, activation: UUID? = nil,
         activationIsCurrent: @escaping () -> Bool = { true },
         onLoginStarted: @escaping (UUID) -> Void = { _ in },
         onAuthenticated: @escaping (ReaderLoginResult) -> Void = { _ in },
         onLoginFinished: @escaping (UUID) -> Void = { _ in }, introductionStyle: Bool = false) {
        self.onBusyChanged = onBusyChanged; self.lifetime = lifetime; self.newsletterOptIn = newsletterOptIn
        self.activation = activation; self.activationIsCurrent = activationIsCurrent
        self.onLoginStarted = onLoginStarted; self.onAuthenticated = onAuthenticated
        self.onLoginFinished = onLoginFinished; self.introductionStyle = introductionStyle
        _signInService = ObservedObject(wrappedValue: GoogleSignInService.shared)
    }

    /// Uses only the caller's original prompt and injected provider service.
    /// No shared login/Auth lookup belongs to a reauthentication button.
    init(reauthenticationPrompt: ReaderGoogleReauthenticationPrompt,
         presentation: ReaderGoogleReauthenticationPrompt.Presentation) {
        reauthentication = (reauthenticationPrompt, presentation)
        introductionStyle = true
        _signInService = ObservedObject(wrappedValue: reauthenticationPrompt.service)
    }
    private var busy: Bool { reauthentication?.presentation.isWorking ?? isLoading }
    
    var body: some View {
        Button(action: startSignIn) {
            HStack(spacing: 12) {
                Image("GoogleSignInMark").resizable().scaledToFit().frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                if busy {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .scaleEffect(0.8)
                }
                
                Text("Fortsæt med Google")
                    .font(.headline)
                    .foregroundColor(.black)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, introductionStyle ? 16 : 0)
            .padding(.vertical, introductionStyle || dynamicTypeSize.isAccessibilitySize ? 12 : 0)
            .frame(maxWidth: .infinity)
            .frame(height: introductionStyle || dynamicTypeSize.isAccessibilitySize ? nil : 50)
            .frame(minHeight: introductionStyle ? 48 : 50)
            .background(Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
        .disabled(busy)
        .accessibilityLabel(LocalizedStringKey(reauthentication == nil ? "Fortsæt med Google" : "Bekræft identitet med Google"))
        .accessibilityIdentifier(reauthentication == nil ? "account.google.signIn" : "account.google.reauthenticate")
        .onChange(of: activation, initial: true) { _, value in
            guard reauthentication == nil else { return }
            guard let value, value != consumedActivation else { return }
            consumedActivation = value
            guard activationIsCurrent() else { return }
            startSignIn()
        }
        .alert("Kunne ikke logge ind", isPresented: reauthentication == nil ? $signInService.showErrorDialog : .constant(false)) {
            Button("OK") { signInService.dismissErrorDialog() }
        } message: {
            Text(LocalizedStringKey(signInService.errorMessage ?? "Prøv igen."))
        }
        .onDisappear {
            if let original = reauthentication { original.prompt.cancel(action: original.presentation.action) }
        }
    }

    private func startSignIn() {
        if let original = reauthentication {
            guard isEnabled, !busy,
                  original.prompt.presentation?.id == original.presentation.id else { return }
            let action = original.presentation.action
            Task { @MainActor in await original.prompt.start(action: action) }
            return
        }
        guard isEnabled, !isLoading, lifetime?.isInvalidated != true else { return }
        // Both direct taps and the completed-presentation activation capture
        // the original context and consent before creating any async task.
        guard let original = signInService.captureSignIn(newsletterOptIn: newsletterOptIn()) else { return }
        let registration = lifetime?.register { signInService.cancel(original) }
        operation = original
        onLoginStarted(original.actionID)
        guard operation === original, lifetime?.isInvalidated != true,
              AuthService.shared.loginFeedbackIsCurrent(original) else {
            signInService.cancel(original)
            if let registration { lifetime?.finish(registration) }
            if operation === original { operation = nil }
            onLoginFinished(original.actionID)
            return
        }
        isLoading = true
        onBusyChanged(true)
        Task { @MainActor in
            defer { onLoginFinished(original.actionID) }
            await signInService.signIn(ticket: original)
            guard operation === original else {
                if let registration { lifetime?.finish(registration) }
                return
            }
            if lifetime?.isInvalidated != true, let session = AuthService.shared.session,
               let result = AuthService.shared.acceptedLoginResult(original, session: session) {
                onAuthenticated(result)
            }
            if let registration { lifetime?.finish(registration) }
            guard operation === original else { return }
            operation = nil
            isLoading = false
            onBusyChanged(false)
        }
    }
}

struct GoogleSignOutButton: View {
    @ObservedObject private var signInService = GoogleSignInService.shared
    
    var body: some View {
        Button(action: {
            signInService.signOut()
        }) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.title2)
                    .foregroundColor(.white)
                
                Text("Log ud")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.red)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
            )
        }
    }
}
