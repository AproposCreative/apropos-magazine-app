#if DEBUG && targetEnvironment(simulator)
import FirebaseCore
import SwiftUI

/// Exercises the actual article control and FavoritesModel using only memory.
@MainActor
private final class LocalFavoriteButtonFixture: ObservableObject {
    enum Scenario: String { case normal, pending, localFailure, readFailure, removal, retryABA }
    @Published private(set) var ready = false
    @Published private(set) var oldCompletion = "Ingen gammel kvittering"
    let model: FavoritesModel
    let scenario: Scenario
    let article = Article(id: "favorite-control-article", name: "Historier, der fortjener din tid", slug: "favorite-control-article",
        content: "", intro: "", topicID: "culture", isDraft: false, lastPublished: "2026-10-24T12:00:00Z", contentRevision: "local-1")
    private let memory: Memory
    private var started = false
    @MainActor private final class Memory {
        var records: [FavoritesNamespace: FavoritesRecord] = [:]
        var holdWrites = false
        var failNext = false
        var failFirstRead = false
        private var pending: [@MainActor () -> Void] = []
        var storage: FavoritesModel.Storage {
            .init(read: { [weak self] namespace, complete in
                guard let self else { complete(.failure(FavoritesJournalFailure.readFailed)); return }
                if self.failFirstRead {
                    self.failFirstRead = false; complete(.failure(FavoritesJournalFailure.readFailed))
                } else { complete(.success(self.records[namespace])) }
            },
                  write: { [weak self] namespace, record, expected, complete in
                guard let self else { complete(.failure(FavoritesJournalFailure.writeFailed)); return }
                let operation: @MainActor () -> Void = { [self] in
                    if self.failNext { self.failNext = false; complete(.failure(FavoritesJournalFailure.writeFailed)); return }
                    guard self.records[namespace]?.recordRevision == expected else {
                        complete(.failure(FavoritesJournalFailure.staleRevision)); return
                    }
                    self.records[namespace] = record; complete(.success(()))
                }
                if self.holdWrites { self.pending.append(operation) } else { operation() }
            })
        }
        func release() {
            holdWrites = false
            let work = pending; pending.removeAll()
            work.forEach { $0() }
        }
    }
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-FavoriteButtonScenario"), arguments.indices.contains(index + 1) {
            scenario = Scenario(rawValue: arguments[index + 1]) ?? .normal
        } else { scenario = .normal }
        let memory = Memory(); self.memory = memory; model = FavoritesModel(storage: memory.storage)
    }
    func start() async {
        guard !started else { return }; started = true
        if scenario == .removal || scenario == .retryABA {
            let context = FavoritesContext.confirmed(userID: "local-favorite-A")
            if let namespace = context.namespace { memory.records[namespace] = FavoritesRecord(articles: [article]) }
            model.changeContext(to: context)
            await recover()
            if let mutation = model.setFavorite(article, enabled: false), let ticket = await model.beginDispatch(mutation) {
                _ = await model.finishDispatch(ticket, result: .failed)
            }
        } else {
            memory.failFirstRead = scenario == .readFailure
            model.changeContext(to: .guest)
            memory.holdWrites = scenario == .pending
            memory.failNext = scenario == .localFailure
        }
        ready = true
    }
    func toggle(generation: UUID) {
        guard model.snapshot.generation == generation else { return }
        let selected = model.snapshot.articles.contains { $0.id == article.id }
        _ = model.setFavorite(article, enabled: !selected)
    }
    func retry(generation: UUID) {
        guard model.snapshot.generation == generation else { return }
        if scenario == .retryABA {
            Task { @MainActor [weak self] in
                guard let self, self.model.snapshot.generation == generation,
                      let mutation = self.model.retryMutation(articleID: self.article.id),
                      let ticket = await self.model.beginDispatch(mutation) else { return }
                self.model.changeContext(to: .confirmed(userID: "local-favorite-B"))
                self.model.changeContext(to: .confirmed(userID: "local-favorite-A"))
                let accepted = await self.model.finishDispatch(ticket, result: .acknowledged)
                self.oldCompletion = accepted ? "FEJL: gammel kvittering accepteret" : "Gammel kvittering afvist"
                await self.recover()
            }
        } else if scenario == .removal {
            Task { @MainActor [weak self] in
                guard let self, self.model.snapshot.generation == generation,
                      let mutation = self.model.retryMutation(articleID: self.article.id),
                      let ticket = await self.model.beginDispatch(mutation) else { return }
                _ = await self.model.finishDispatch(ticket, result: .acknowledged)
                if let observation = self.model.observationTicket() {
                    _ = self.model.applyRemote(.init(articles: [], isFromCache: false, hasPendingWrites: false), ticket: observation)
                }
            }
        } else { model.retryStorage() }
    }
    func release() { memory.release() }
    private func recover() async {
        guard let ticket = model.recoveryTicket(), model.beginRecovery(ticket) else { return }
        _ = await model.finishRecovery(ticket, success: true)
    }
}

struct LocalFavoriteButtonSmokeView: View {
    @StateObject private var fixture = LocalFavoriteButtonFixture()
    var body: some View { LocalFavoriteButtonContent(fixture: fixture, model: fixture.model) }
}

private struct LocalFavoriteButtonContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var fixture: LocalFavoriteButtonFixture
    @ObservedObject var model: FavoritesModel
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase startet")
                        .accessibilityIdentifier("favorite.fixture.firebase")
                    Text(fixture.ready ? "Klar" : "Klargør lokale data")
                        .accessibilityIdentifier("favorite.fixture.ready")
                    Text(dynamicTypeSize.isAccessibilitySize ? "Tilgængelighedstekst" : "Normal tekst")
                        .accessibilityIdentifier("favorite.fixture.textSize")
                    Text("Lagring: \(String(describing: model.snapshot.state))")
                        .accessibilityIdentifier("favorite.fixture.state")
                    Text(fixture.oldCompletion).accessibilityIdentifier("favorite.fixture.oldCompletion")
                    Button("Aflevér lokal gemning", action: fixture.release)
                        .accessibilityIdentifier("favorite.fixture.release")
                }
                .font(.caption).dynamicTypeSize(.large)
                .padding(12).frame(maxWidth: .infinity)
                .background(.quaternary)
                HStack {
                    Text("Gem til senere").font(.headline)
                    Spacer()
                    ArticleFavoriteControl(model: model, articleID: fixture.article.id,
                        toggle: fixture.toggle, retry: fixture.retry)
                }
                .padding(.horizontal, 24)
                Spacer(minLength: 0)
            }
            .navigationTitle("Artikelhandling")
            .navigationBarTitleDisplayMode(.inline)
            .task { await fixture.start() }
        }
    }
}
#endif
