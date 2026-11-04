#if DEBUG && targetEnvironment(simulator)
import Combine
import FirebaseCore
import SwiftUI

@MainActor
private final class LocalFavoritesFixture: ObservableObject {
    @Published private(set) var owner = "Uafklaret"
    @Published var failWrites = false { didSet { memory.failWrites = failWrites } }
    @Published var showCloudControls = false
    @Published private var runtime: FavoritesRuntime
    var model: FavoritesModel { runtime.model }
    var offline: FavoritesOfflineCoordinator { runtime.offline! }
    var pendingCount: Int { model.snapshot.pendingArticleIDs.count }
    var recoveryCount: Int { memory.drains.count }
    var favoriteCount: Int { memory.favoriteRequests.count }
    var profileCount: Int { memory.profiles.count }
    var localProfileState: String { memory.localProfileUID == nil ? "Lokal profil: ikke indlæst" : "Lokal profil: indlæst" }
    private let memory: Memory
    private var oldDownload: FavoritesOfflineCoordinator.AccessTicket?
    let article = Article(id: "fixture-article", name: "Journalistik til fordybelse", slug: "fixture-article",
                          content: "<p>Lokalt testindhold.</p>", intro: "", topicID: "fixture-topic",
                          isDraft: false, lastPublished: "2026-10-20T12:00:00Z", contentRevision: "fixture-revision")
    @MainActor private final class Memory {
        enum Failure: Error { case write, restarted }
        struct FavoriteRequest { let mutation: FavoritesModel.Mutation;let continuation: CheckedContinuation<Void, Error> }
        var failWrites = false
        var records: [FavoritesNamespace: Data] = [:]
        var bodies: [String: Article] = [:]
        var server: [FavoritesNamespace: [String: Article]] = [:]
        var drains: [CheckedContinuation<Void, Error>] = []
        var favoriteRequests: [FavoriteRequest] = []
        var profiles: [CheckedContinuation<Void, Error>] = []
        var localProfileUID: String?
        // Complete fixture profiles already exist. The mirror only updates a
        // bookmark field and never constructs either local or server profiles.
        var serverProfiles: [String: Set<String>] = ["fixture-account-a": [], "fixture-account-b": []]
        var onChange: (() -> Void)?
        var storage: FavoritesModel.Storage {
            .init(read: { [self] namespace, completion in
                completion(Result { try records[namespace].map { try FavoritesRecordCodec.decode($0, namespace: namespace) } })
            }, write: { [self] namespace, record, expectedRevision, completion in
                completion(Result {
                    guard !failWrites else { throw Failure.write }
                    let prior = try records[namespace].map { try FavoritesRecordCodec.decode($0, namespace: namespace) }
                    guard prior?.recordRevision == expectedRevision else { throw Failure.write }
                    records[namespace] = try FavoritesRecordCodec.encode(record, namespace: namespace)
                })
            })
        }
        func drain() async throws {
            try await withCheckedThrowingContinuation { drains.append($0);onChange?() }
        }
        func favorite(_ mutation: FavoritesModel.Mutation) async throws {
            try await withCheckedThrowingContinuation { favoriteRequests.append(.init(mutation: mutation, continuation: $0));onChange?() }
        }
        func profile(uid: String, articleID: String, saved: Bool) async throws {
            try await withCheckedThrowingContinuation { profiles.append($0);onChange?() }
            guard var existing = serverProfiles[uid] else { throw Failure.write }
            if saved { existing.insert(articleID) } else { existing.remove(articleID) }
            serverProfiles[uid] = existing
        }
        func completeDrain() { guard !drains.isEmpty else { return };drains.removeFirst().resume();onChange?() }
        func completeFavorite() {
            guard !favoriteRequests.isEmpty else { return }
            let request = favoriteRequests.removeFirst(), mutation = request.mutation
            var articles = server[mutation.namespace] ?? [:]
            if mutation.enabled { articles[mutation.articleID] = mutation.article } else { articles.removeValue(forKey: mutation.articleID) }
            server[mutation.namespace] = articles;request.continuation.resume();onChange?()
        }
        func completeProfile() { guard !profiles.isEmpty else { return };profiles.removeFirst().resume();onChange?() }
        func discardDrains() {
            let previous = drains;drains = [];previous.forEach { $0.resume(throwing: Failure.restarted) };onChange?()
        }
    }
    init() {
        let memory = Memory();self.memory = memory
        runtime = Self.makeRuntime(memory)
        runtime.prepareIfNeeded()
        memory.onChange = { [weak self] in self?.objectWillChange.send() }
    }
    private static func makeRuntime(_ memory: Memory) -> FavoritesRuntime {
        FavoritesRuntime(disabled: false, requiresAccountForSaving: false, storageFactory: { memory.storage },
            drainPendingWrites: { _ in try await memory.drain() },
            writeFavorite: { mutation, _ in try await memory.favorite(mutation) },
            offlineFactory: { model in FavoritesOfflineCoordinator(model: model,
                storage: .init(read: { memory.bodies[$0] }, write: { memory.bodies[$0] = $1 }),
                permitsBody: { _ in true }, effects: .init(cacheImages: { _, _ in }, audioAsset: { _ in nil },
                audioIsCached: { _ in false }, pinAudio: { _, _, _ in }, releaseAudio: { _, _, _ in }, scheduleRetry: { _, _ in {} })) },
            profileSet: { ticket, uid, model in
                try await FavoritesProfileMirror.perform(model: model, ticket: ticket, expectedUserID: uid,
                    effects: .init(identity: {
                        let current = model.context == .confirmed(userID: uid) ? uid : nil
                        return .init(actualUID: current, canonicalUID: current)
                    }, updateExisting: { originalUID, articleID, saved in
                        try await memory.profile(uid: originalUID, articleID: articleID, saved: saved)
                    }))
            })
    }
    func select(_ owner: String) {
        switch owner {
        case "Konto A": runtime.changeAccountContext(userID: "fixture-account-a")
        case "Konto B": runtime.changeAccountContext(userID: "fixture-account-b")
        case "Gæst": runtime.changeAccountContext(userID: nil)
        default: runtime.suspendForAccountChange()
        }
        self.owner = owner
    }
    func save() {
        runtime.setFavorite(article, enabled: true)
        if owner == "Konto A", oldDownload == nil { oldDownload = offline.captureAccess(articleID: article.id) }
    }
    func remove() { runtime.setFavorite(article, enabled: false) }
    func completeDrain() { memory.completeDrain() }
    func completeFavorite() { memory.completeFavorite() }
    func completeProfile() { memory.completeProfile() }
    func confirmServer() {
        guard let namespace = model.context.namespace, let ticket = model.observationTicket() else { return }
        let articles = Array((memory.server[namespace] ?? [:]).values)
        model.applyRemote(.init(articles: articles, isFromCache: false, hasPendingWrites: false), ticket: ticket)
    }
    func restore() {
        // Simulated new process, only before provider work starts. A real active
        // SDK write is never cancelled or declared complete by this control.
        guard memory.favoriteRequests.isEmpty, memory.profiles.isEmpty else { return }
        let previousOwner = owner
        runtime.suspendForAccountChange();memory.discardDrains()
        runtime = Self.makeRuntime(memory);runtime.prepareIfNeeded();select(previousOwner)
    }
    func downloadCurrent() {
        guard let ticket = offline.captureAccess(articleID: article.id) else { return }
        offline.saveBody(article, ticket: ticket);objectWillChange.send()
    }
    func downloadOld() { if let ticket = oldDownload { offline.saveBody(article, ticket: ticket) };objectWillChange.send() }
    func retry(generation: UUID) { runtime.retryCurrentChanges(generation: generation) }
}

@MainActor
struct LocalFavoritesSmokeView: View {
    @StateObject private var fixture = LocalFavoritesFixture()
    var body: some View { LocalFavoritesContent(fixture: fixture, model: fixture.model) }
}

@MainActor
private struct LocalFavoritesContent: View {
    @ObservedObject var fixture: LocalFavoritesFixture
    @ObservedObject var model: FavoritesModel
    var body: some View {
        NavigationStack {
            Form {
                Section("Kun lokale testdata") {
                    Text("Favoritmodel, offlineadgang og fejlfelt er de samme som i appen. Konti, gemninger og downloads simuleres i hukommelsen. Ingen tjenester startes.")
                        .font(.footnote).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("favorites.fixture.intro")
                    Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase er startet")
                        .accessibilityIdentifier("favorites.fixture.firebase")
                    ForEach(["Uafklaret", "Gæst", "Konto A", "Konto B"], id: \.self) { owner in
                        Button(owner) { fixture.select(owner) }
                            .tint(.primary).foregroundStyle(.primary)
                            .accessibilityIdentifier("favorites.owner.\(owner)")
                    }
                }
                Section("Gemte artikler") {
                    Text("Aktiv læser: \(fixture.owner)").accessibilityIdentifier("favorites.fixture.owner")
                    Text("Gemte artikler: \(model.snapshot.articles.count)").accessibilityIdentifier("favorites.fixture.count")
                    Text(fixture.offline.body(articleID: fixture.article.id) == nil ? "Ingen ejet offlineartikel" : "Offlineartikel tilgængelig")
                        .accessibilityIdentifier("favorites.fixture.offline")
                    Button("Gem artikel") { fixture.save() }
                        .tint(.primary).foregroundStyle(.primary).accessibilityIdentifier("favorites.fixture.save")
                    Button("Hent artikel for den aktive læser") { fixture.downloadCurrent() }
                        .tint(.primary).foregroundStyle(.primary).accessibilityIdentifier("favorites.fixture.download")
                    Button("Aflevér gammel download fra A") { fixture.downloadOld() }
                        .tint(.primary).foregroundStyle(.primary).accessibilityIdentifier("favorites.fixture.oldDownload")
                    Toggle("Simulér gemmefejl", isOn: $fixture.failWrites).accessibilityIdentifier("favorites.fixture.failWrites")
                    Text(model.snapshot.state == .ready ? "Gemt i testens hukommelseslager" : "Lagring ikke bekræftet")
                        .accessibilityIdentifier("favorites.fixture.storage")
                }
                Section {
                    Button(fixture.showCloudControls ? "Skjul test af synkronisering" : "Test synkronisering") {
                        fixture.showCloudControls.toggle()
                    }
                    .accessibilityIdentifier("favorites.fixture.cloudControls")
                    if fixture.showCloudControls {
                        Text("Ændringer i kø: \(fixture.pendingCount)").accessibilityIdentifier("favorites.fixture.pending")
                        Text("Recovery venter: \(fixture.recoveryCount)").accessibilityIdentifier("favorites.fixture.recovery")
                        Text("Favorit venter: \(fixture.favoriteCount), profil venter: \(fixture.profileCount)").accessibilityIdentifier("favorites.fixture.stages")
                            .accessibilityValue(fixture.localProfileState)
                        Button("Fjern artikel", action: fixture.remove).accessibilityIdentifier("favorites.fixture.remove")
                        Button("Genopret fra testlager", action: fixture.restore).accessibilityIdentifier("favorites.fixture.restore")
                        Button("Afslut lokal recovery", action: fixture.completeDrain).accessibilityIdentifier("favorites.fixture.completeDrain")
                        Button("Aflevér favoritskrivning", action: fixture.completeFavorite).accessibilityIdentifier("favorites.fixture.completeFavorite")
                        Button("Aflevér profilskrivning", action: fixture.completeProfile).accessibilityIdentifier("favorites.fixture.completeProfile")
                        Button("Bekræft simuleret serverliste", action: fixture.confirmServer).accessibilityIdentifier("favorites.fixture.confirmServer")
                    }
                }
                .tint(.primary).foregroundStyle(.primary)
                Section { FavoritesNotice(model: model, retry: fixture.retry) }
            }
            .accessibilityIdentifier("favorites.fixture.form")
            .navigationTitle("Lokale favoritter")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif
