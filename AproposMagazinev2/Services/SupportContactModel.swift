import Foundation
import Combine

/// User-initiated support handoff. All platform effects are required injections;
/// neither construction nor editing opens an app, touches a clipboard or sends mail.
@MainActor
final class SupportContactModel: ObservableObject {
    struct ComposerDraft: Identifiable, Equatable, Sendable {
        let id: UUID
        let recipient: String
        let subject: String
        let body: String
    }
    enum ComposerResult: Equatable, Sendable { case sent, saved, cancelled, failed }
    enum State: Equatable, Sendable {
        case idle, emptyMessage, composing, openingMailApp
        case handedToMail, draftSaved, cancelled, composerFailed
        case mailAppOpened, manualFallback, openingTimedOut
        case addressCopied, messageCopied, copyFailed
    }
    typealias Cancel = @MainActor () -> Void
    typealias Completion = @MainActor (Bool) -> Void
    typealias Scheduler = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Cancel

    @Published private(set) var message = ""
    @Published private(set) var state = State.idle
    @Published private(set) var presentation: ComposerDraft?

    private enum Kind { case composer, mailApp }
    private struct Attempt: Equatable {
        let id: UUID
        let generation: UUID
        let kind: Kind
    }
    private let canCompose: @MainActor () -> Bool
    private let openURL: @MainActor (URL, @escaping Completion) -> Void
    private let copy: @MainActor (String) -> Bool
    private let schedule: Scheduler
    private let openingTimeout: TimeInterval
    private var generation = UUID()
    private var active: Attempt?
    private var cancelOpening: Cancel?

    init(canCompose: @escaping @MainActor () -> Bool,
         openURL: @escaping @MainActor (URL, @escaping Completion) -> Void,
         copy: @escaping @MainActor (String) -> Bool,
         schedule: @escaping Scheduler,
         openingTimeout: TimeInterval = 8) {
        precondition(openingTimeout.isFinite && openingTimeout > 0 && openingTimeout <= 60)
        self.canCompose = canCompose
        self.openURL = openURL
        self.copy = copy
        self.schedule = schedule
        self.openingTimeout = openingTimeout
    }

    func updateMessage(_ text: String) {
        guard text != message else { return }
        let token = invalidateObservation()
        guard generation == token else { return }
        message = text
        guard generation == token else { return }
        state = .idle
    }

    func openMailDraft() {
        guard active == nil else { return } // Coalesce repeated taps on the same handoff.
        let token = invalidateObservation()
        guard generation == token else { return }
        guard SupportContactPolicy.isMeaningfulMessage(message) else { state = .emptyMessage;return }
        let body = message
        guard body.utf8.count <= SupportContactPolicy.maximumComposerBodyBytes else { state = .manualFallback;return }
        let available = canCompose()
        guard generation == token else { return }
        if available {
            let attempt = Attempt(id: UUID(), generation: token, kind: .composer)
            active = attempt
            state = .composing
            guard isCurrent(attempt) else { return }
            presentation = ComposerDraft(id: attempt.id, recipient: SupportContactPolicy.recipient,
                                         subject: SupportContactPolicy.subject, body: body)
            return
        }
        guard let url = SupportContactPolicy.mailtoURL(body: body) else { state = .manualFallback;return }
        let attempt = Attempt(id: UUID(), generation: token, kind: .mailApp)
        active = attempt
        state = .openingMailApp
        guard isCurrent(attempt) else { return }
        let cancel = schedule(openingTimeout) { [weak self] in self?.completeOpening(attempt, state: .openingTimedOut) }
        // A synchronous deadline or injected reentrant action may have closed the
        // observation before its cancellation handle was returned. Do not open late.
        guard isCurrent(attempt) else { cancel();return }
        cancelOpening = cancel
        openURL(url) { [weak self] accepted in
            self?.completeOpening(attempt, state: accepted ? .mailAppOpened : .manualFallback)
        }
    }

    func finishComposer(id: UUID, result: ComposerResult) {
        guard let attempt = active, attempt.id == id, attempt.kind == .composer,
              presentation?.id == id, isCurrent(attempt) else { return }
        active = nil
        presentation = nil
        guard generation == attempt.generation else { return }
        switch result {
        case .sent: state = .handedToMail
        case .saved: state = .draftSaved
        case .cancelled: state = .cancelled
        case .failed: state = .composerFailed
        }
    }

    func composerDismissed(id: UUID) { finishComposer(id: id, result: .cancelled) }

    /// Closes evidence and platform presentation. Ownership of the text belongs to
    /// the presenting view; create a new model for a different reader context.
    func invalidateContext() {
        let token = invalidateObservation()
        guard generation == token else { return }
        state = .idle
    }

    func copyAddress() { copyExplicitly(SupportContactPolicy.recipient, success: .addressCopied) }
    func copyMessage() {
        guard SupportContactPolicy.isMeaningfulMessage(message) else {
            let token = invalidateObservation()
            if generation == token { state = .emptyMessage }
            return
        }
        copyExplicitly(message, success: .messageCopied)
    }

    private func copyExplicitly(_ text: String, success: State) {
        let token = invalidateObservation()
        guard generation == token else { return }
        let copied = copy(text)
        guard generation == token else { return }
        state = copied ? success : .copyFailed
    }

    private func completeOpening(_ attempt: Attempt, state completed: State) {
        guard attempt.kind == .mailApp, isCurrent(attempt) else { return }
        active = nil
        let cancel = cancelOpening
        cancelOpening = nil
        cancel?()
        guard generation == attempt.generation else { return }
        state = completed
    }

    @discardableResult
    private func invalidateObservation() -> UUID {
        let token = UUID()
        generation = token
        active = nil
        let cancel = cancelOpening
        cancelOpening = nil
        presentation = nil
        cancel?()
        return token
    }
    private func isCurrent(_ attempt: Attempt) -> Bool { active == attempt && generation == attempt.generation }
}
