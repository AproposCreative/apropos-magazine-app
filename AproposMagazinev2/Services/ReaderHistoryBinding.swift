import Foundation

/// The reader's actual callback boundary. Documents retain their original
/// article/owner ticket; a later renderer update cannot lend them a new owner.
@MainActor
final class ReaderHistoryBinding {
    struct Session: Equatable, Sendable {
        let id: UUID
        let articleID: String
        fileprivate let owner: ReadingHistoryModel.ArticleTicket
    }
    struct Document: Equatable, Sendable {
        let id: String
        fileprivate let session: Session
    }
    private struct Active {
        let session: Session
        let onProgress: @MainActor (Double) -> Void
    }
    private let model: ReadingHistoryModel
    private let markRead: @MainActor (ReadingHistoryModel.ArticleTicket) -> Void
    private var active: Active?
    private var document: Document?
    private var readyDocument: Document?
    private var lastProgress: Double?
    private var isStarting = false
    private var isRecording = false

    init(model: ReadingHistoryModel,
         markRead: @escaping @MainActor (ReadingHistoryModel.ArticleTicket) -> Void) {
        self.model = model
        self.markRead = markRead
    }

    func beginArticle(articleID: String, onOpen: @MainActor () -> Void,
                      onProgress: @escaping @MainActor (Double) -> Void) -> Session? {
        guard !isStarting else { return nil }
        isStarting = true
        defer { isStarting = false }
        if let previous = active?.session { endSession(previous) }
        let generation = model.snapshot.generation
        guard let owner = model.beginArticle(articleID: articleID),
              model.snapshot.generation == generation, model.isCurrent(owner) else { return nil }
        let session = Session(id: UUID(), articleID: articleID, owner: owner)
        active = Active(session: session, onProgress: onProgress)
        markRead(owner)
        guard isCurrent(session) else { discardIfCurrent(session); return nil }
        onOpen()
        guard isCurrent(session) else { discardIfCurrent(session); return nil }
        return session
    }

    func isCurrent(_ session: Session) -> Bool {
        active?.session == session && model.isCurrent(session.owner)
    }

    func beginDocument(_ session: Session, documentID: String) -> Document? {
        guard isCurrent(session), UUID(uuidString: documentID) != nil else { return nil }
        let next = Document(id: documentID, session: session)
        document = next
        readyDocument = nil
        lastProgress = nil
        return next
    }

    /// Called only for a measured height from the accepted current HTML document.
    func markDocumentReady(_ proposed: Document) {
        guard document == proposed, isCurrent(proposed.session) else { return }
        readyDocument = proposed
    }

    func progressHandler(for proposed: Document) -> @MainActor (Double) -> Void {
        { [weak self] value in self?.record(value, document: proposed) }
    }

    @discardableResult
    func record(_ value: Double, document proposed: Document) -> Bool {
        guard !isRecording, document == proposed, readyDocument == proposed,
              isCurrent(proposed.session), value.isFinite, (0...1).contains(value),
              let originalEffect = active?.onProgress else { return false }
        let quantized = (value * 20).rounded() / 20
        if let lastProgress, abs(quantized - lastProgress) < 0.049 { return false }
        isRecording = true
        defer { isRecording = false }
        lastProgress = quantized
        model.saveProgress(quantized, ticket: proposed.session.owner)
        guard document == proposed, readyDocument == proposed, isCurrent(proposed.session) else { return false }
        originalEffect(quantized)
        return document == proposed && isCurrent(proposed.session)
    }

    func endDocument(_ proposed: Document) {
        guard document == proposed else { return }
        document = nil
        readyDocument = nil
        lastProgress = nil
    }

    func endSession(_ proposed: Session) {
        guard active?.session == proposed else { return }
        discardIfCurrent(proposed)
        model.endArticle(proposed.owner)
    }

    private func discardIfCurrent(_ proposed: Session) {
        guard active?.session == proposed else { return }
        active = nil
        document = nil
        readyDocument = nil
        lastProgress = nil
    }
}
