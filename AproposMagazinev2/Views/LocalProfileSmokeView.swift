#if DEBUG && targetEnvironment(simulator)
import FirebaseCore
import SwiftUI

@MainActor
private final class LocalProfileFixture: ObservableObject {
    let state: UserProfileState
    let coordinator: UserProfileCoordinator
    private let memory: Memory
    var pendingLabel: String {
        let owners = memory.reads.map { $0.seed.uid }
        return "Ventende svar: " + (owners.isEmpty ? "ingen" : owners.joined(separator: ", "))
    }
    var hasPending: Bool { !memory.reads.isEmpty }
    var phase: String {
        let snapshot = state.snapshot
        if snapshot.errorMessage != nil { return "Profil: fejl" }
        if snapshot.isLoading { return "Profil: hentes" }
        switch snapshot.context {
        case .unresolved: return "Profil: uafklaret"
        case .guest: return "Profil: gæst"
        case .account: return snapshot.loaded ? "Profil: klar" : "Profil: venter"
        }
    }
    @MainActor private final class Memory {
        struct Read {
            let seed: UserProfile
            let continuation: CheckedContinuation<UserProfileCoordinator.ReadResult, Error>
        }
        var actualUID: String?, canonicalUID: String?
        var reads: [Read] = []
        var onChange: (() -> Void)?
        enum Failure: Error { case read }
        func read(_ seed: UserProfile) async throws -> UserProfileCoordinator.ReadResult {
            try await withCheckedThrowingContinuation { reads.append(.init(seed: seed, continuation: $0));onChange?() }
        }
        func reply(newest: Bool, fail: Bool = false) {
            guard !reads.isEmpty else { return }
            let read = reads.remove(at: newest ? reads.count - 1 : 0)
            if fail { read.continuation.resume(throwing: Failure.read) }
            else { read.continuation.resume(returning: .init(profile: read.seed, isFromCache: false)) }
            onChange?()
        }
    }
    init() {
        let state = UserProfileState(), memory = Memory()
        self.state = state;self.memory = memory
        coordinator = UserProfileCoordinator(state: state, effects: .init(capturePermission: { { true } }, identity: {
            .init(actualUID: memory.actualUID, canonicalUID: memory.canonicalUID)
        }, read: { seed, _, _, stillCurrent in
            guard stillCurrent() else { throw CancellationError() }
            return try await memory.read(seed)
        }, write: { _, _, stillCurrent in guard stillCurrent() else { throw CancellationError() } },
        subscribe: { _, owns in _ = owns() }, unsubscribe: { _, owns in _ = owns() }, updateFCM: { _, owns in _ = owns() }))
        memory.onChange = { [weak self] in self?.objectWillChange.send() }
        coordinator.start()
    }
    func select(_ uid: String?) {
        memory.actualUID = uid;memory.canonicalUID = uid
        coordinator.changeAccountContext(userID: uid)
        if let uid { coordinator.load(Self.profile(uid)) }
        else { coordinator.clearIfConfirmedGuest() }
    }
    func retry() {
        guard let uid = state.snapshot.context.userID else { return }
        coordinator.load(Self.profile(uid))
    }
    /// Retire only the visible load through actual state admission/cancellation;
    /// its held physical reply remains available and cannot become a profile.
    func retirePendingLoad() {
        guard let uid = state.snapshot.context.userID,
              let ticket = state.beginLoad(userID: uid) else { return }
        _ = state.cancelLoad(ticket: ticket)
    }
    func newest() { memory.reply(newest: true) }
    func oldest() { memory.reply(newest: false) }
    func fail() { memory.reply(newest: true, fail: true) }
    private static func profile(_ uid: String) -> UserProfile {
        UserProfile(uid: uid, email: uid.lowercased() + "@example.test", displayName: "Læser " + uid, photoURL: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000), lastLoginAt: Date(timeIntervalSince1970: 1_700_000_100),
            favoriteCategories: [], favoriteAuthors: [], notificationPreferences: .init(), readingPreferences: .init(),
            readArticles: [], bookmarkedArticles: [], readingProgress: [:])
    }
}

@MainActor
struct LocalProfileSmokeView: View {
    @StateObject private var fixture = LocalProfileFixture()
    var body: some View { LocalProfileContent(fixture: fixture, state: fixture.state) }
}
@MainActor
private struct LocalProfileContent: View {
    @ObservedObject var fixture: LocalProfileFixture
    @ObservedObject var state: UserProfileState
    @State private var showingSettings = false
    @State private var loginRequests = 0
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Kun lokale testdata. Profiltilstand, koordinator og kontorække er de samme som i appen. Svar afleveres manuelt, og ingen tjenester startes.")
                        .font(.footnote).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("profile.fixture.intro")
                    Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase er startet")
                        .font(.footnote).accessibilityIdentifier("profile.fixture.firebase")
                    ProfileAccountSummary(snapshot: state.snapshot)
                    Text(fixture.phase).font(.subheadline).accessibilityIdentifier("profile.fixture.phase")
                    Text(fixture.pendingLabel).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("profile.fixture.pending")
                    HStack {
                        Button("Konto A") { fixture.select("A") }.accessibilityIdentifier("profile.fixture.accountA")
                        Button("Konto B") { fixture.select("B") }.accessibilityIdentifier("profile.fixture.accountB")
                        Button("Gæst") { fixture.select(nil) }.accessibilityIdentifier("profile.fixture.guest")
                    }
                    .buttonStyle(.bordered)
                    Button("Hent profil igen", action: fixture.retry).buttonStyle(.bordered)
                        .accessibilityIdentifier("profile.fixture.retry")
                    Button("Afslut ventende profil lokalt", action: fixture.retirePendingLoad)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("profile.fixture.retire")
                    Divider()
                    VStack(spacing: 12) {
                        Button(action: fixture.newest) {
                            Text("Nyeste svar").fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
                        }
                        .accessibilityIdentifier("profile.fixture.newest")
                        Button(action: fixture.oldest) {
                            Text("Ældste svar").fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
                        }
                        .accessibilityIdentifier("profile.fixture.oldest")
                        Button(action: fixture.fail) {
                            Text("Vis fejl").fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
                        }
                        .accessibilityIdentifier("profile.fixture.fail")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!fixture.hasPending)
                }
                .padding(20)
            }
            .accessibilityIdentifier("profile.fixture.form")
            .tint(.primary)
            .navigationTitle("Lokal profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Indstillinger") { showingSettings = true }
                        .accessibilityIdentifier("profile.fixture.settings")
                }
            }
            .sheet(isPresented: $showingSettings) {
                LocalProfileSettings(fixture: fixture, state: state, loginRequests: $loginRequests)
            }
        }
    }
}

/// Only the account section and version footer are product UI. The separate
/// fixture section exposes deterministic callbacks without any auth services.
@MainActor
private struct LocalProfileSettings: View {
    @ObservedObject var fixture: LocalProfileFixture
    @ObservedObject var state: UserProfileState
    @Binding var loginRequests: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                SettingsAccountSection(snapshot: state.snapshot, onLogin: { loginRequests += 1 }, onRetry: fixture.retry)
                Section("Lokal teststatus") {
                    Text("Login åbnet lokalt: \(loginRequests)")
                        .accessibilityIdentifier("profile.settings.loginCount")
                    Text(fixture.phase)
                        .accessibilityIdentifier("profile.settings.phase")
                    Text(fixture.pendingLabel)
                        .accessibilityIdentifier("profile.settings.pending")
                    Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase er startet")
                        .accessibilityIdentifier("profile.settings.firebase")
                    Button("Aflever nyeste profilsvar", action: fixture.newest)
                        .disabled(!fixture.hasPending)
                        .accessibilityIdentifier("profile.settings.newest")
                }
                SettingsVersionFooter()
            }
            .accessibilityIdentifier("profile.fixture.settingsList")
            .navigationTitle("Indstillinger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Færdig") { dismiss() }
                        .accessibilityIdentifier("profile.settings.close")
                }
            }
        }
    }
}
#endif
