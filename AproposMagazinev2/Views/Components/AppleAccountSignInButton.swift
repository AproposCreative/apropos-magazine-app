import AuthenticationServices
import SwiftUI

@MainActor
final class AppleLoginCallbacks {
    private(set) var actionID: UUID?
    let onFinished: (UUID) -> Void
    init(onFinished: @escaping (UUID) -> Void) { self.onFinished = onFinished }
    func started(_ id: UUID) { actionID = id }
    func finish(_ id: UUID) {
        guard actionID == id else { return }
        actionID = nil
        onFinished(id)
    }
}

struct AppleAccountSignInButton: View {
    var onBusyChanged: (Bool) -> Void = { _ in }
    var lifetime: AccountLoginLifetime? = nil
    var activation: UUID? = nil
    var activationIsCurrent: () -> Bool = { true }
    var introductionStyle = false
    @ScaledMetric(relativeTo: .headline) private var introductionButtonHeight: CGFloat = 48
    @StateObject private var flow: AppleAccountFlowModel
    @State private var callbacks: AppleLoginCallbacks
    private var providerFactory: AppleAuthorizationButton.Coordinator.ProviderFactory?

    init(onBusyChanged: @escaping (Bool) -> Void = { _ in }, lifetime: AccountLoginLifetime? = nil,
         newsletterOptIn: @escaping () -> Bool = { false }, activation: UUID? = nil,
         activationIsCurrent: @escaping () -> Bool = { true },
         onLoginStarted: @escaping (UUID) -> Void = { _ in },
         onAuthenticated: @escaping (ReaderLoginResult) -> Void = { _ in },
         onLoginFinished: @escaping (UUID) -> Void = { _ in }, introductionStyle: Bool = false) {
        self.onBusyChanged = onBusyChanged
        self.lifetime = lifetime
        self.activation = activation
        self.activationIsCurrent = activationIsCurrent
        self.introductionStyle = introductionStyle
        let callbacks = AppleLoginCallbacks(onFinished: onLoginFinished)
        _callbacks = State(initialValue: callbacks)
        _flow = StateObject(wrappedValue: AppleAccountFlowModel(capture: {
        let auth = AuthService.shared
        let ticket = try auth.captureLogin(.apple, newsletterOptIn: newsletterOptIn())
        callbacks.started(ticket.actionID)
        onLoginStarted(ticket.actionID)
        do {
            guard lifetime?.isInvalidated != true else { auth.cancelLogin(ticket); throw CancellationError() }
            try auth.beginLoginProvider(ticket)
        } catch { callbacks.finish(ticket.actionID); throw error }
        return .init(perform: { token, nonce, name in
            let session = try await auth.signInWithApple(idToken: token, rawNonce: nonce, fullName: name, ticket: ticket)
            if lifetime?.isInvalidated != true, let session,
               let result = auth.acceptedLoginResult(ticket, session: session) { onAuthenticated(result) }
            return session
        }, providerReturned: { try auth.loginProviderReturned(ticket) },
           providerFailed: {
               defer { callbacks.finish(ticket.actionID) }
               return auth.loginProviderFailed(ticket)
           }, cancel: { auth.cancelLogin(ticket) },
           feedbackIsCurrent: { auth.loginFeedbackIsCurrent(ticket) })
    }))
    }

    /// The caller owns the original reauthentication action and supplies its
    /// exact flow. This initializer never resolves AuthService.shared.
    init(reauthenticationFlow: AppleAccountFlowModel,
         onBusyChanged: @escaping (Bool) -> Void = { _ in },
         lifetime: AccountLoginLifetime? = nil, activation: UUID? = nil,
         activationIsCurrent: @escaping () -> Bool = { true },
         providerFactory: AppleAuthorizationButton.Coordinator.ProviderFactory? = nil) {
        self.onBusyChanged = onBusyChanged; self.lifetime = lifetime
        self.activation = activation; self.activationIsCurrent = activationIsCurrent
        self.providerFactory = providerFactory
        _callbacks = State(initialValue: AppleLoginCallbacks(onFinished: { _ in }))
        _flow = StateObject(wrappedValue: reauthenticationFlow)
    }

    var body: some View {
        AppleAuthorizationButton(flow: flow, callbacks: callbacks, lifetime: lifetime, activation: activation,
                                 activationIsCurrent: activationIsCurrent, introductionStyle: introductionStyle, providerFactory: providerFactory)
            .frame(maxWidth: .infinity)
            .frame(height: introductionStyle ? max(48, introductionButtonHeight) : 50)
            .overlay(RoundedRectangle(cornerRadius: introductionStyle ? 12 : 6).stroke(Color(.systemGray4), lineWidth: 1))
            .disabled(flow.isWorking)
            .accessibilityLabel(LocalizedStringKey(flow.isReauthentication ? "Bekræft identitet med Apple" : "Fortsæt med Apple"))
            .accessibilityIdentifier(flow.isReauthentication ? "account.apple.reauthenticate" : "account.apple.signIn")
            .onChange(of: flow.isWorking) { _, working in onBusyChanged(working) }
            .alert(flow.isReauthentication ? "Kunne ikke bekræfte identitet" : "Kunne ikke logge ind", isPresented: Binding(
                get: { flow.errorMessage != nil },
                set: { if !$0 { flow.clearError() } }
            )) {
                Button("OK") { flow.clearError() }
            } message: { Text(LocalizedStringKey(flow.errorMessage ?? "Prøv igen.")) }
    }
}

struct AppleAuthorizationButton: UIViewRepresentable {
    @ObservedObject var flow: AppleAccountFlowModel
    let callbacks: AppleLoginCallbacks
    let lifetime: AccountLoginLifetime?
    let activation: UUID?
    let activationIsCurrent: () -> Bool
    let introductionStyle: Bool
    let providerFactory: Coordinator.ProviderFactory?
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(flow: flow, callbacks: callbacks, lifetime: lifetime, providerFactory: providerFactory) }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: flow.isReauthentication ? .continue : .signIn, style: introductionStyle ? .white : .black)
        button.cornerRadius = introductionStyle ? 12 : 6
        button.addTarget(context.coordinator, action: #selector(Coordinator.signIn), for: .touchUpInside)
        context.coordinator.button = button
        return button
    }

    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        button.isEnabled = isEnabled && !flow.isWorking
        context.coordinator.activate(activation, isCurrent: activationIsCurrent)
    }

    static func dismantleUIView(_ button: ASAuthorizationAppleIDButton, coordinator: Coordinator) {
        button.removeTarget(coordinator, action: #selector(Coordinator.signIn), for: .touchUpInside)
        coordinator.viewDetached()
    }

    @MainActor
    final class Coordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        /// One concrete provider request. Tests inject a plain object and local
        /// callbacks; live effects below alone create the Apple controller.
        struct ProviderRequest {
            let identity: AnyObject
            let perform: @MainActor () -> Void
            let cancel: @MainActor () -> Void
            let release: @MainActor () -> Void
        }
        typealias ProviderFactory = @MainActor (AppleSignInChallenge, Coordinator) -> ProviderRequest

        let flow: AppleAccountFlowModel
        weak var button: ASAuthorizationAppleIDButton?
        private weak var window: UIWindow?
        private var provider: ProviderRequest?
        private var ticketID: UUID?
        private var loginActionID: UUID?
        private let callbacks: AppleLoginCallbacks
        private let lifetime: AccountLoginLifetime?
        private let providerFactory: ProviderFactory?
        private let presentationReady: (@MainActor () -> Bool)?
        private var registration: UUID?
        private var consumedActivation: UUID?
        private var latestActivation: UUID?
        private var detached = false
        private var starting = false
        private var performed = false
        private var cancellationRequested = false
        // Apple's delegate is weak. Keep the original provider/exchange request
        // alive until its physical callback and any subsequent SDK work finish.
        private var requestLifetime: Coordinator?

        init(flow: AppleAccountFlowModel, callbacks: AppleLoginCallbacks, lifetime: AccountLoginLifetime?,
             providerFactory: ProviderFactory? = nil, presentationReady: (@MainActor () -> Bool)? = nil) {
            self.flow = flow; self.callbacks = callbacks; self.lifetime = lifetime
            self.providerFactory = providerFactory; self.presentationReady = presentationReady
        }

        func activate(_ activation: UUID?, isCurrent: @escaping () -> Bool) {
            latestActivation = activation
            guard let activation, activation != consumedActivation else { return }
            consumedActivation = activation
            guard isCurrent(), latestActivation == activation, !detached else { return }
            let originalIsCurrent: () -> Bool
            if flow.isReauthentication {
                // The injected flow belongs to the original deletion action.
                // Reauthentication must not look up a shared login service.
                originalIsCurrent = isCurrent
            } else {
                let canonical = AuthService.shared.state, original = canonical.contextTicket()
                originalIsCurrent = { canonical.isCurrent(original) && isCurrent() }
            }
            // Avoid observable publication from updateUIView itself.
            Task { @MainActor [weak self] in
                guard let self, !self.detached, self.latestActivation == activation,
                      originalIsCurrent(), !self.detached, self.latestActivation == activation else { return }
                self.signIn()
            }
        }

        @objc func signIn() {
            guard !starting, ticketID == nil, !detached, lifetime?.isInvalidated != true else { return }
            starting = true
            defer { starting = false }
            let ready = presentationReady?() ?? (button?.isEnabled == true && button?.window != nil)
            guard ready, !detached, lifetime?.isInvalidated != true, ticketID == nil,
                  let challenge = flow.begin() else { return }
            ticketID = challenge.id
            loginActionID = callbacks.actionID
            requestLifetime = self
            performed = false; cancellationRequested = false
            // begin publishes synchronously; teardown may already have happened.
            guard !detached, lifetime?.isInvalidated != true, flow.canPresent(ticketID: challenge.id),
                  !detached, lifetime?.isInvalidated != true else {
                flow.providerCancelled(ticketID: challenge.id); finish(ticketID: challenge.id); return
            }
            window = button?.window
            let request = providerFactory?(challenge, self) ?? makeLiveRequest(challenge)
            provider = request
            registration = lifetime?.register { [weak self] in self?.cancelPresentation() }
            guard !detached, !cancellationRequested, lifetime?.isInvalidated != true,
                  flow.canPresent(ticketID: challenge.id),
                  !detached, !cancellationRequested, lifetime?.isInvalidated != true else {
                releaseProvider(); flow.providerCancelled(ticketID: challenge.id); finish(ticketID: challenge.id); return
            }
            performed = true // Reserve before the launcher can synchronously callback.
            request.perform()
        }

        private func makeLiveRequest(_ challenge: AppleSignInChallenge) -> ProviderRequest {
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = flow.isReauthentication ? [] : [.email, .fullName]
            request.nonce = challenge.hashedNonce; request.state = challenge.state
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self; controller.presentationContextProvider = self
            return ProviderRequest(identity: controller, perform: { controller.performRequests() },
                cancel: { controller.cancel() }, release: {
                    controller.delegate = nil; controller.presentationContextProvider = nil
                })
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            window ?? ASPresentationAnchor()
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                receive(identity: controller, error: AppleAccountFlowError.invalidIdentity); return
            }
            receive(identity: controller, response: .init(identityToken: credential.identityToken,
                state: credential.state, fullName: credential.fullName, userID: credential.user))
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            receive(identity: controller, error: error)
        }

        /// The actual delegate and injected local provider use this same entry.
        /// Retire the concrete controller synchronously before any main-actor hop.
        func receive(identity: AnyObject, response: AppleIdentityResponse) {
            guard performed, let original = provider, original.identity === identity, let ticketID else { return }
            releaseProvider()
            Task { [self] in
                await flow.complete(ticketID: ticketID, response: response)
                finish(ticketID: ticketID)
            }
        }

        func receive(identity: AnyObject, error: Error) {
            guard performed, let original = provider, original.identity === identity, let ticketID else { return }
            releaseProvider()
            if (error as? ASAuthorizationError)?.code == .canceled { flow.providerCancelled(ticketID: ticketID) }
            else { flow.fail(ticketID: ticketID, error: error) }
            finish(ticketID: ticketID)
        }

        func viewDetached() {
            detached = true; latestActivation = nil
            // Login success can remove its button while its valid sheet remains.
            // A reauth presentation instead always revokes its original intent.
            if flow.isReauthentication || lifetime == nil || lifetime?.isInvalidated == true { cancelPresentation() }
        }
        func cancelPresentation() {
            guard let ticketID, !cancellationRequested else { return }
            cancellationRequested = true
            flow.cancel(ticketID: ticketID)
            // Logical cancellation never proves that the physical request ended.
            if performed { provider?.cancel() }
        }
        private func releaseProvider() {
            let old = provider
            provider = nil // Duplicate/reentrant callbacks are no longer admitted.
            old?.release()
        }
        private func finish(ticketID: UUID) {
            guard self.ticketID == ticketID else { return }
            let originalRegistration = registration
            let originalLoginAction = loginActionID
            self.ticketID = nil
            registration = nil
            loginActionID = nil
            performed = false
            requestLifetime = nil
            // Retirement must precede callbacks: login completion can reenter
            // signIn, and old cleanup must never clear the new physical owner.
            if let originalRegistration { lifetime?.finish(originalRegistration) }
            if let originalLoginAction { callbacks.finish(originalLoginAction) }
        }
    }
}
