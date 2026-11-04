#if DEBUG && targetEnvironment(simulator)
import FirebaseCore
import SwiftUI

/// Clean native capture data for the existing injected account presentations.
/// No AuthService, provider, defaults, network or real signup is constructed.
@MainActor
private final class LocalFigmaAccountReferenceFixture: ObservableObject {
    let session: ReaderAccountSession
    let canonical: CanonicalSessionState
    let preferences: ReaderPreferencesModel
    let actions: ReaderAccountActions
    let newsletter: ReaderNewsletterSignupModel
    let topics = [
        Topic(id: "design", name: "Design"),
        Topic(id: "music", name: "Musik"),
        Topic(id: "film", name: "Serier & Film")
    ]
    @Published private(set) var ready = false
    private var beganPreparation = false

    init() {
        let local = ReaderAccountSession(uid: "figma-reference-reader",
            email: "reader@example.invalid", isEmailVerified: true)
        session = local
        let state = CanonicalSessionState()
        _ = state.adopt(local)
        canonical = state
        let model = ReaderPreferencesModel(capturePermission: { { true } }, identity: {
            .init(actualUID: state.snapshot.userID, canonicalUID: state.snapshot.userID)
        }, load: { original, owns in
            guard owns(), original.userID == local.uid else { throw CancellationError() }
            return .init(preferences: ReaderPreferences(interestTopicIDs: ["design", "music"],
                onboardingCompleted: true), isFromCache: false)
        }, save: { _, _ in
            // An accidental capture-time save cannot report a successful write.
            throw CancellationError()
        }, schedule: { _ in {} })
        preferences = model
        actions = ReaderAccountActions(canonical: state, preferences: model,
            verify: { _ in }, refresh: { _ in })
        newsletter = ReaderNewsletterSignupModel(canonical: state) { request, context in
            guard state.isCurrent(context), context.userID == local.uid else { throw CancellationError() }
            // Only the unchecked idle form is captured. No fabricated membership.
            return .init(status: .unavailable, requestID: request.requestID)
        }
    }

    func prepare() async {
        guard !beganPreparation else { return }
        beganPreparation = true
        preferences.start()
        guard let original = preferences.changeContext(to: .account(session.uid)) else { return }
        await preferences.load(original)
        guard !Task.isCancelled else { return }
        ready = preferences.snapshot.loaded && !preferences.snapshot.isLoading
            && preferences.snapshot.userID == session.uid
            && canonical.snapshot.session == session
    }
}

@MainActor
struct LocalFigmaAccountReferenceView: View {
    enum Screen: String {
        case signedIn = "account-signedin"
        case newsletter = "newsletter-manual"
    }

    let screen: Screen
    let onClose: () -> Void
    @StateObject private var fixture = LocalFigmaAccountReferenceFixture()

    init(screen: Screen, onClose: @escaping () -> Void) {
        self.screen = screen
        self.onClose = onClose
    }

    var body: some View {
        Group {
            switch screen {
            case .signedIn:
                NavigationStack {
                    ReaderAccountSheetContent(canonical: fixture.canonical,
                        preferences: fixture.preferences, actions: fixture.actions,
                        topics: fixture.topics, onDone: onClose, newsletter: { email in
                            AnyView(ReaderNewsletterSignupContent(email: email,
                                canonical: fixture.canonical, model: fixture.newsletter,
                                context: fixture.canonical.contextTicket()))
                        }) {
                            EmptyView()
                        } extraContent: {
                            EmptyView()
                        }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Luk", action: onClose)
                            }
                        }
                        .tint(.primary)
                }
            case .newsletter:
                ReaderNewsletterSignupContent(email: fixture.session.email,
                    canonical: fixture.canonical, model: fixture.newsletter,
                    context: fixture.canonical.contextTicket())
            }
        }
        .task { await fixture.prepare() }
        .overlay(alignment: .bottomLeading) { metadata }
    }

    private var metadata: some View {
        let info = Bundle.main.infoDictionary ?? [:]
        let value: [String: Any] = [
            "screen": screen.rawValue,
            "ready": fixture.ready,
            "firebaseStarted": FirebaseApp.allApps != nil,
            "version": info["CFBundleShortVersionString"] as? String ?? "",
            "build": info["CFBundleVersion"] as? String ?? "",
            "email": fixture.session.email,
            "verified": fixture.session.isEmailVerified,
            "preferencesLoaded": fixture.preferences.snapshot.loaded,
            "selectedTopicIDs": fixture.preferences.preferences.interestTopicIDs,
            "newsletterStatus": String(describing: fixture.newsletter.status),
            "dataSource": "local-memory-no-provider-or-service"
        ]
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data()
        return Text("Reference")
            .font(.system(size: 1)).foregroundStyle(.clear)
            .frame(width: 1, height: 1).clipped()
            .accessibilityIdentifier("figma.account.reference.metadata")
            .accessibilityLabel("Lokal native kontoreference")
            .accessibilityValue(String(decoding: data, as: UTF8.self))
            .allowsHitTesting(false)
    }
}
#endif
