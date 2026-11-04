#if DEBUG && targetEnvironment(simulator)
import Combine
import FirebaseCore
import SwiftUI
import UIKit

/// Manual replies surround the real committed states and account action seam.
/// No AuthService, Firestore, APNs, defaults or remote web view is constructed.
@MainActor
private final class LocalReaderAccountFixture: ObservableObject {
    let canonical: CanonicalSessionState
    let preferences: ReaderPreferencesModel
    let actions: ReaderAccountActions
    let newsletter: ReaderNewsletterSignupModel
    private let memory: Memory
    private var newsletterObservation: AnyCancellable?
    private let publication = CanonicalAccountPublication()
    @Published private(set) var heldActions: [@MainActor () async -> Void] = []
    @Published private(set) var completedHeldActions = 0
    @Published var holdNextAction = false
    let topics = [Topic(id: "design", name: "Design"), Topic(id: "music", name: "Musik"), Topic(id: "film", name: "Film")]

    @MainActor
    private final class Memory {
        struct Read {
            let uid: String
            let continuation: CheckedContinuation<ReaderPreferencesModel.ReadResult, Error>
        }
        struct Verification {
            let ticket: CanonicalSessionState.VerificationTicket
            let continuation: CheckedContinuation<Void, Never>
        }
        struct NewsletterReply {
            let request: ReaderNewsletterSignupModel.Request
            let continuation: CheckedContinuation<ReaderNewsletterSignupModel.Response, Never>
        }
        var actualUID: String?
        var remoteChoices: [String: [String]] = [:]
        var reads: [Read] = []
        var verifications: [Verification] = []
        var completedVerifications = 0
        var newsletterRequests: [ReaderNewsletterSignupModel.Request] = []
        var newsletterReplies: [NewsletterReply] = []
        var completedNewsletterResponses = 0
        var writes: [(String, ReaderPreferences)] = []
        var failNextSave = false
        var onChange: (() -> Void)?
        enum Failure: Error { case local }
        func read(_ uid: String) async throws -> ReaderPreferencesModel.ReadResult {
            try await withCheckedThrowingContinuation { continuation in
                reads.append(.init(uid: uid, continuation: continuation)); onChange?()
            }
        }
        func replyRead(fail: Bool) {
            guard !reads.isEmpty else { return }
            let read = reads.removeLast()
            if fail { read.continuation.resume(throwing: Failure.local) }
            else {
                let value = ReaderPreferences(interestTopicIDs: remoteChoices[read.uid] ?? (read.uid == "A" ? ["design"] : ["music"]), onboardingCompleted: true)
                read.continuation.resume(returning: .init(preferences: value, isFromCache: false))
            }
            onChange?()
        }
        func save(_ request: ReaderPreferencesModel.SaveRequest) throws {
            let fail = failNextSave; failNextSave = false
            if fail { onChange?(); throw Failure.local }
            writes.append((request.userID, request.preferences)); onChange?()
        }
        func verify(_ ticket: CanonicalSessionState.VerificationTicket) async {
            await withCheckedContinuation { continuation in
                verifications.append(.init(ticket: ticket, continuation: continuation)); onChange?()
            }
        }
        func replyVerification() {
            guard !verifications.isEmpty else { return }
            verifications.removeFirst().continuation.resume(); onChange?()
        }
        func sendNewsletter(_ request: ReaderNewsletterSignupModel.Request) async -> ReaderNewsletterSignupModel.Response {
            newsletterRequests.append(request)
            let response: ReaderNewsletterSignupModel.Response = await withCheckedContinuation { continuation in
                newsletterReplies.append(.init(request: request, continuation: continuation)); onChange?()
            }
            completedNewsletterResponses += 1; onChange?()
            return response
        }
        func replyNewsletter(_ status: ReaderNewsletterSignupModel.ResponseStatus, challenge: String? = nil) {
            guard !newsletterReplies.isEmpty else { return }
            let reply = newsletterReplies.removeFirst()
            reply.continuation.resume(returning: .init(status: status, requestID: reply.request.requestID,
                reconfirmationChallenge: challenge))
            onChange?()
        }
    }

    init() {
        let state = CanonicalSessionState(), memory = Memory()
        canonical = state; self.memory = memory
        let preferences = ReaderPreferencesModel(capturePermission: { { true } }, identity: {
            .init(actualUID: memory.actualUID, canonicalUID: state.snapshot.userID)
        }, load: { original, owns in
            guard owns(), let uid = original.userID else { throw CancellationError() }
            return try await memory.read(uid)
        }, save: { request, owns in
            guard owns() else { throw CancellationError() }
            try memory.save(request)
        }, schedule: { _ in {} })
        self.preferences = preferences
        newsletter = ReaderNewsletterSignupModel(canonical: state) { request, _ in
            await memory.sendNewsletter(request)
        }
        let verification = ReaderAccountVerificationCoordinator(state: state, effects: .init(
            actualUserID: { memory.actualUID }, send: { ticket, owns in
                guard owns() else { throw CancellationError() }
                await memory.verify(ticket)
            }, refresh: { original, owns in
                guard owns(), let uid = original.userID else { throw CancellationError() }
                return .init(uid: uid, email: uid.lowercased() + "@example.test", isEmailVerified: true)
            }))
        actions = ReaderAccountActions(canonical: state, preferences: preferences, verify: { original in
            await verification.sendVerification(context: original)
            // Waitable evidence AFTER the actual production coordinator has
            // attempted result adoption, not merely after continuation release.
            memory.completedVerifications += 1; memory.onChange?()
        }, refresh: { original in
            try await verification.refreshSession(context: original)
        })
        memory.onChange = { [weak self] in self?.objectWillChange.send() }
        newsletterObservation = newsletter.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        preferences.start()
        select(nil)
    }
    var pendingLabel: String {
        "Ventende svar: " + (memory.reads.isEmpty ? "ingen" : memory.reads.map(\.uid).joined(separator: ", "))
    }
    var writeLabel: String { "Gemninger: \(memory.writes.count)" }
    var heldLabel: String { "Handlinger: \(heldActions.count) venter · \(completedHeldActions) afsluttet" }
    var verificationLabel: String { "Bekræftelser: \(memory.verifications.count) venter · \(memory.completedVerifications) afsluttet" }
    var hasReads: Bool { !memory.reads.isEmpty }
    var hasVerifications: Bool { !memory.verifications.isEmpty }
    var failNextSave: Bool { memory.failNextSave }
    var hasNewsletterReplies: Bool { !memory.newsletterReplies.isEmpty }
    var newsletterReport: String {
        let value: [String: Any] = [
            "firebaseStarted": FirebaseApp.allApps != nil,
            "systemTextCategory": UIApplication.shared.preferredContentSizeCategory.rawValue,
            "systemAccessibility": UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory,
            "canonicalUID": canonical.snapshot.userID ?? "guest",
            "canonicalEmail": canonical.snapshot.session?.email ?? "",
            "canonicalEmailVerified": canonical.snapshot.session?.isEmailVerified ?? false,
            "status": String(describing: newsletter.status),
            "requestID": newsletter.requestID ?? "",
            "pendingReplies": memory.newsletterReplies.count,
            "completedResponses": memory.completedNewsletterResponses,
            "requests": memory.newsletterRequests.map { request in
                ["requestID": request.requestID, "expectedUserID": request.expectedUserID,
                 "expectedEmail": request.expectedEmail, "consent": request.consent,
                 "consentVersion": request.consentVersion, "source": request.source,
                 "reconfirmationChallenge": request.reconfirmationChallenge as Any? ?? NSNull()] as [String: Any]
            }
        ]
        let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
    func select(_ uid: String?) {
        memory.actualUID = uid
        var original: ReaderPreferencesModel.ContextTicket?
        var canonicalContext: CanonicalSessionState.ContextTicket?
        let revocationsCurrent: () -> Bool = {
            guard let original else { return false }
            return original.context == .confirmed(userID: uid) && self.preferences.isCurrent(original)
        }
        publication.performReaderTransition(expectedUserID: uid, currentUserID: { memory.actualUID },
            revokeProfile: { true }, revokePreferences: {
                original = self.preferences.changeContext(to: .confirmed(userID: uid))
                return revocationsCurrent()
            }, revocationsCurrent: revocationsCurrent, dependentSteps: [], commitCanonical: {
                canonicalContext = self.canonical.adopt(uid.map {
                    .init(uid: $0, email: $0.lowercased() + "@example.test", isEmailVerified: false)
                }, stillPermitted: revocationsCurrent)
                return canonicalContext.map(self.canonical.isCurrent) ?? false
            }, startLoads: {
                guard let original, original.userID != nil, let canonicalContext else { return }
                Task {
                    guard self.canonical.isCurrent(canonicalContext) else { return }
                    await self.preferences.load(original)
                }
            })
    }
    func schedule(_ action: @escaping @MainActor () async -> Void) {
        if holdNextAction { holdNextAction = false; heldActions.append(action) }
        else { Task { await action() } }
    }
    func releaseAction() {
        guard !heldActions.isEmpty else { return }
        let action = heldActions.removeFirst()
        Task { await action(); completedHeldActions += 1 }
    }
    func refreshRemoteChoices() {
        guard let uid = memory.actualUID,
              let request = preferences.captureRefresh(context: preferences.contextTicket()) else { return }
        memory.remoteChoices[uid] = ["design", "film"]
        Task { await preferences.refresh(request) }
    }
    func replyRead() { memory.replyRead(fail: false) }
    func failRead() { memory.replyRead(fail: true) }
    func failSave() { memory.failNextSave = true; objectWillChange.send() }
    func replyVerification() { memory.replyVerification() }
    func replyNewsletterPending() { memory.replyNewsletter(.pending) }
    func replyNewsletterSuccess() { memory.replyNewsletter(.subscribed) }
    func replyNewsletterChallenge() {
        memory.replyNewsletter(.reconfirmationRequired, challenge: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")
    }
    func replyNewsletterSpentChallenge() { memory.replyNewsletter(.reconfirmationRequired) }
}

@MainActor
struct LocalReaderAccountSmokeView: View {
    @StateObject private var fixture = LocalReaderAccountFixture()
    @State private var showAccount = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Kun lokale testdata") {
                    Text("Kontoopsætningen bruger appens fælles komponenter og lokale svar. Ingen tjenester startes.")
                    Button("Læserkonto") { showAccount = true }
                        .accessibilityIdentifier("reader.fixture.open")
                }
            }
            .navigationTitle("Lokale indstillinger")
            .sheet(isPresented: $showAccount) {
                LocalReaderAccountSheet(fixture: fixture, isPresented: $showAccount)
            }
        }
    }
}

@MainActor
private struct LocalReaderAccountSheet: View {
    @ObservedObject var fixture: LocalReaderAccountFixture
    @Binding var isPresented: Bool
    var body: some View {
        NavigationStack {
            ReaderAccountSheetContent(canonical: fixture.canonical, preferences: fixture.preferences,
                actions: fixture.actions, topics: fixture.topics, schedule: fixture.schedule,
                onDone: { isPresented = false }, newsletter: {
                    AnyView(LocalReaderNewsletterSheet(fixture: fixture, email: $0,
                        context: fixture.canonical.contextTicket()))
                }) {
                    Section {
                        Text("Du kan læse magasinet uden en konto.")
                            .accessibilityIdentifier("reader.account.guest")
                    }
                } extraContent: {
                    Section("Lokal testtransport") {
                        Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase er startet")
                            .font(.footnote).accessibilityIdentifier("reader.fixture.firebase")
                        HStack {
                            Button("A") { fixture.select("A") }.accessibilityIdentifier("reader.fixture.accountA")
                            Button("B") { fixture.select("B") }.accessibilityIdentifier("reader.fixture.accountB")
                            Button("Gæst") { fixture.select(nil) }.accessibilityIdentifier("reader.fixture.guest")
                        }.buttonStyle(.bordered)
                        Text(fixture.pendingLabel).font(.footnote)
                            .accessibilityIdentifier("reader.fixture.pending")
                        HStack {
                            Button("Svar", action: fixture.replyRead).accessibilityIdentifier("reader.fixture.reply")
                            Button("Læsefejl", action: fixture.failRead).accessibilityIdentifier("reader.fixture.failRead")
                        }.buttonStyle(.bordered).disabled(!fixture.hasReads)
                        Button("Opdater fra anden enhed", action: fixture.refreshRemoteChoices)
                            .accessibilityIdentifier("reader.fixture.refreshPreferences")
                        Toggle("Hold næste handling", isOn: $fixture.holdNextAction)
                            .accessibilityIdentifier("reader.fixture.hold")
                        Text(fixture.heldLabel).font(.footnote).accessibilityIdentifier("reader.fixture.held")
                        Button("Frigiv handling", action: fixture.releaseAction)
                            .accessibilityIdentifier("reader.fixture.release").disabled(fixture.heldActions.isEmpty)
                        Text(fixture.writeLabel).font(.footnote).accessibilityIdentifier("reader.fixture.writes")
                        Button(fixture.failNextSave ? "Næste gemning fejler" : "Lad næste gemning fejle", action: fixture.failSave)
                            .accessibilityIdentifier("reader.fixture.failSave")
                        Text(fixture.verificationLabel).font(.footnote).accessibilityIdentifier("reader.fixture.verifications")
                        Button("Aflever bekræftelse", action: fixture.replyVerification)
                            .accessibilityIdentifier("reader.fixture.replyVerification").disabled(!fixture.hasVerifications)
                        Button("Aflever ventende nyhedsbrevssvar", action: fixture.replyNewsletterSuccess)
                            .accessibilityIdentifier("reader.fixture.newsletter.lateSuccess")
                            .disabled(!fixture.hasNewsletterReplies)
                        Text(fixture.newsletterReport).font(.system(size: 1)).lineLimit(1)
                            .accessibilityIdentifier("reader.fixture.newsletter.report")
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Luk") { isPresented = false } }
                }
                .tint(.primary)
        }
        .presentationDetents([.large])
    }
}

@MainActor
private struct LocalReaderNewsletterSheet: View {
    @ObservedObject var fixture: LocalReaderAccountFixture
    let email: String
    let context: CanonicalSessionState.ContextTicket
    var body: some View {
        // Allocate reply controls outside the real form. An outer safe-area
        // inset can overlay NavigationStack's Form at accessibility sizes.
        VStack(spacing: 0) {
            ReaderNewsletterSignupContent(email: email, canonical: fixture.canonical,
                model: fixture.newsletter, context: context)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 4) {
                Text("Kun lokale svar · intet netværk").font(.caption2)
                HStack {
                    Button("Afventer", action: fixture.replyNewsletterPending)
                        .accessibilityIdentifier("reader.newsletter.fixture.pending")
                        .disabled(!fixture.hasNewsletterReplies)
                    Button("Bekræft", action: fixture.replyNewsletterSuccess)
                        .accessibilityIdentifier("reader.newsletter.fixture.success")
                        .disabled(!fixture.hasNewsletterReplies)
                    Button("Skift til B") { fixture.select("B") }
                        .accessibilityIdentifier("reader.newsletter.fixture.accountB")
                }
                .buttonStyle(.bordered).frame(minHeight: 44)
                HStack {
                    Button("Afmeldt", action: fixture.replyNewsletterChallenge)
                        .accessibilityIdentifier("reader.newsletter.fixture.challenge")
                    Button("Udløbet", action: fixture.replyNewsletterSpentChallenge)
                        .accessibilityIdentifier("reader.newsletter.fixture.spentChallenge")
                }.buttonStyle(.bordered).frame(minHeight: 44).disabled(!fixture.hasNewsletterReplies)
                Text(fixture.newsletterReport).font(.system(size: 1)).lineLimit(1)
                    .accessibilityIdentifier("reader.newsletter.fixture.report")
            }
            .dynamicTypeSize(.large).padding(8).background(.regularMaterial)
        }
    }
}
#endif
