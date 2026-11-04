import Combine
import Foundation

/// Committed feed state. Reserve before permission reads and willChange so a
/// nested live result cannot be overwritten by a suspended cache assignment.
@MainActor
final class ArticleFeedPublication: ObservableObject {
    struct Snapshot: Equatable {
        let articles: [Article]
        let revision: UUID
    }
    struct Receipt: Equatable { fileprivate let revision: UUID }
    nonisolated let objectWillChange = ObservableObjectPublisher()
    private let subject = PassthroughSubject<Snapshot, Never>()
    private var operation = UUID()
    private var notifying = false
    private(set) var snapshot = Snapshot(articles: [], revision: UUID())
    var changes: AnyPublisher<Snapshot, Never> {
        subject.filter { [weak self] in self?.snapshot.revision == $0.revision }.eraseToAnyPublisher()
    }

    @discardableResult
    func replace(_ articles: [Article], stillPermitted: () -> Bool = { true }) -> Receipt? {
        let original = UUID()
        operation = original
        guard permitted(original, stillPermitted) else { return nil }
        if snapshot.articles == articles { return Receipt(revision: snapshot.revision) }
        if !notifying {
            notifying = true
            objectWillChange.send()
            notifying = false
        }
        guard permitted(original, stillPermitted) else { return nil }
        snapshot = Snapshot(articles: articles, revision: original)
        subject.send(snapshot)
        guard snapshot.revision == original else { return nil }
        return Receipt(revision: original)
    }

    func isCurrent(_ receipt: Receipt) -> Bool { snapshot.revision == receipt.revision }
    private func permitted(_ token: UUID, _ check: () -> Bool) -> Bool {
        guard operation == token else { return false }
        let allowed = check()
        return allowed && operation == token
    }
}

/// The actual startup admission seam used around cache hydration. A successful
/// network response (including empty), a newer start or explicit replacement
/// invalidates the original cache proposal before any publishing/effects.
@MainActor
final class ArticleFeedStartupAdmission {
    struct Ticket: Equatable {
        fileprivate let epoch: UUID
        fileprivate let feedRevision: UUID
    }
    private var epoch = UUID()
    private var accepted: (ticket: Ticket, receipt: ArticleFeedPublication.Receipt)?
    let feed: ArticleFeedPublication
    init(feed: ArticleFeedPublication) { self.feed = feed }
    func capture() -> Ticket { Ticket(epoch: epoch, feedRevision: feed.snapshot.revision) }
    func invalidate() { epoch = UUID(); accepted = nil }
    func isCurrent(_ original: Ticket) -> Bool {
        guard original.epoch == epoch else { return false }
        if feed.snapshot.revision == original.feedRevision { return true }
        return accepted.map { $0.ticket == original && feed.isCurrent($0.receipt) } ?? false
    }
    @discardableResult
    func adopt(_ articles: [Article], original: Ticket, stillPermitted: () -> Bool = { true }) -> ArticleFeedPublication.Receipt? {
        guard let receipt = feed.replace(articles, stillPermitted: {
            guard self.isCurrent(original) else { return false }
            let allowed = stillPermitted()
            return allowed && self.isCurrent(original)
        }), original.epoch == epoch, feed.isCurrent(receipt) else { return nil }
        // The original ticket may follow its OWN accepted commit for guarded
        // widget effects, but cannot borrow any other subsequent feed revision.
        accepted = (original, receipt)
        return receipt
    }
}
