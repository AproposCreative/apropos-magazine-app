import Foundation

/// Immutable policy inputs; account identifiers are discarded after selection.
struct RecommendationHistoryInput: Equatable {
    let generation: UUID
    let sourceRevision: UInt64
    let articles: [Article]
    let favorites: [Article]
    let interestTopicIDs: [String]
    let readArticleIDs: Set<String>

    static func == (lhs: Self, rhs: Self) -> Bool {
        // Scroll-only revisions do not change recommendation relevance.
        lhs.generation == rhs.generation && lhs.articles == rhs.articles
            && lhs.favorites == rhs.favorites && lhs.interestTopicIDs == rhs.interestTopicIDs
            && lhs.readArticleIDs == rhs.readArticleIDs
    }
}

enum RecommendationHistorySelection {
    static func isCurrent(_ delivered: ReadingHistorySnapshot, comparedTo current: ReadingHistorySnapshot) -> Bool {
        delivered.generation == current.generation && delivered.revision == current.revision
    }

    static func validatedProfileIDs(_ ids: [String]) -> [String] {
        ids.suffix(ReadingHistoryRecordCodec.maximumEntries).filter(ReadingHistoryRecordCodec.isValidID)
    }

    static func ownsFavorites(context: ReadingHistoryContext, generation: UUID, canonicalUserID: String?,
                              expectedUserID: String, expectedGeneration: UUID) -> Bool {
        canonicalUserID == expectedUserID && context == .confirmed(userID: expectedUserID) && generation == expectedGeneration
    }

    /// Context and snapshot must come from the same synchronous model observation.
    /// The production caller rejects a superseded post-state delivery first.
    static func capture(context: ReadingHistoryContext, snapshot: ReadingHistorySnapshot,
                        canonicalUserID: String?, profileUserID: String?, profileReadIDs: [String],
                        articles: [Article], favorites: [Article], favoritesGeneration: UUID?,
                        interestTopicIDs: [String]) -> RecommendationHistoryInput? {
        guard context != .unresolved, context == .confirmed(userID: canonicalUserID) else { return nil }
        var ids = Set(snapshot.readArticleIDs)
        if let canonicalUserID, profileUserID == canonicalUserID { ids.formUnion(validatedProfileIDs(profileReadIDs)) }
        return RecommendationHistoryInput(generation: snapshot.generation, sourceRevision: snapshot.revision,
            articles: articles, favorites: canonicalUserID != nil && favoritesGeneration == snapshot.generation ? favorites : [],
            interestTopicIDs: Set(interestTopicIDs).sorted(), readArticleIDs: ids)
    }
}

/// One running calculation and one latest pending input. Ignored cancellation
/// cannot grant an old request a new owner or create parallel policy work.
@MainActor
final class RecommendationHistoryCoordinator {
    struct State {
        let ticket: UUID
        let input: RecommendationHistoryInput?
        let isLoading: Bool
        let recommendations: [(Article, String)]
    }
    typealias Calculate = @MainActor (RecommendationHistoryInput) async -> [(Article, String)]
    private struct Request { let ticket: UUID; let input: RecommendationHistoryInput }
    private let calculate: Calculate
    private let onChange: @MainActor (State) -> Void
    private var currentInput: RecommendationHistoryInput?
    private var ticket = UUID()
    private var pending: Request?
    private var driver: Task<Void, Never>?

    init(calculate: @escaping Calculate, onChange: @escaping @MainActor (State) -> Void) {
        self.calculate = calculate
        self.onChange = onChange
    }
    deinit { driver?.cancel() }
    func isCurrent(_ state: State) -> Bool { state.ticket == ticket }

    func update(_ input: RecommendationHistoryInput?, force: Bool = false) {
        guard force || input != currentInput else { return }
        ticket = UUID()
        currentInput = input
        let own = ticket
        pending = input.map { Request(ticket: own, input: $0) }
        onChange(State(ticket: own, input: input, isLoading: input != nil, recommendations: []))
        guard ticket == own else { return }
        startPendingIfNeeded()
    }
    /// Revoke synchronously before a coalesced refresh captures new inputs.
    func invalidate() { update(nil, force: true) }

    private func startPendingIfNeeded() {
        guard driver == nil, let request = pending, request.ticket == ticket else { return }
        pending = nil
        let calculate = calculate
        driver = Task { @MainActor [weak self] in
            let result = await calculate(request.input)
            self?.finish(request, result: result)
        }
    }
    private func finish(_ request: Request, result: [(Article, String)]) {
        driver = nil
        if request.ticket == ticket {
            onChange(State(ticket: request.ticket, input: request.input, isLoading: false, recommendations: result))
        }
        startPendingIfNeeded()
    }
}
