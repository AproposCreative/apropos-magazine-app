import Combine
import Foundation

/// The shared form captures its immutable payload and operation admission in the
/// button event. Unit/fixture operations use the same form without services.
@MainActor
final class EmailAccountFlowModel: ObservableObject {
    nonisolated let objectWillChange = ObservableObjectPublisher()
    enum Purpose: Equatable { case account, reauthentication(lockedEmail: String) }
    let purpose: Purpose
    var lockedEmail: String? { if case .reauthentication(let email) = purpose { return email }; return nil }
    var isReauthentication: Bool { lockedEmail != nil }
    typealias Perform = (EmailAccountAction, EmailAccountForm) async throws -> ReaderAccountSession?
    struct Operation {
        let perform: () async throws -> ReaderAccountSession?
        var cancel: () -> Void = {}
        var feedbackIsCurrent: () -> Bool = { true }
    }
    struct Submission {
        fileprivate let id: UUID
        fileprivate let action: EmailAccountAction
        fileprivate let operation: Operation
    }
    var form = EmailAccountForm() { didSet { draftRevision = UUID(); objectWillChange.send() } }
    var action = EmailAccountAction.signIn { didSet { objectWillChange.send() } }
    var isWorking: Bool { active != nil }
    private(set) var errorMessage: String? { didSet { objectWillChange.send() } }
    private(set) var statusMessage: String? { didSet { objectWillChange.send() } }
    private(set) var authenticatedSession: ReaderAccountSession? { didSet { objectWillChange.send() } }
    private let captureOperation: (EmailAccountAction, EmailAccountForm) throws -> Operation
    private var active: Submission?
    private var performingID: UUID?
    private var cancelledID: UUID?
    private var admission = UUID()
    private var draftRevision = UUID()

    init(purpose: Purpose = .account, capture: @escaping (EmailAccountAction, EmailAccountForm) throws -> Operation) {
        self.purpose = purpose; captureOperation = capture
        if case .reauthentication(let email) = purpose { form.email = email }
    }
    convenience init(purpose: Purpose = .account, perform: @escaping Perform) {
        self.init(purpose: purpose, capture: { action, fields in Operation(perform: { try await perform(action, fields) }) })
    }
    func clearFeedback() { errorMessage = nil; statusMessage = nil }

    /// The actual SwiftUI button calls this before creating its Task.
    func captureSubmission() -> Submission? {
        guard active == nil else { return nil }
        let event = UUID(); admission = event
        let selectedAction: EmailAccountAction = isReauthentication ? .signIn : action
        let originalDraft = draftRevision
        var submitted = form
        if let lockedEmail { submitted.email = lockedEmail }
        let validation = submitted.validationMessage(for: selectedAction)
        if let validation {
            if isReauthentication { clearPasswords(ifCurrent: originalDraft) }
            guard admission == event, active == nil else { return nil }
            errorMessage = validation
            guard admission == event, active == nil else { return nil }
            statusMessage = nil
            return nil
        }
        do {
            // Reserve the original canonical context before the first observable
            // feedback change can synchronously reenter the account pipeline.
            let operation = try captureOperation(selectedAction, submitted)
            guard admission == event, active == nil else { operation.cancel(); return nil }
            let value = Submission(id: UUID(), action: selectedAction, operation: operation)
            active = value; cancelledID = nil
            if isReauthentication { clearPasswords(ifCurrent: originalDraft) }
            guard active?.id == value.id, cancelledID != value.id else { operation.cancel(); return nil }
            errorMessage = nil
            guard active?.id == value.id, cancelledID != value.id else { operation.cancel(); return nil }
            statusMessage = nil
            guard active?.id == value.id, cancelledID != value.id else { operation.cancel(); return nil }
            authenticatedSession = nil
            guard active?.id == value.id, cancelledID != value.id else { operation.cancel(); return nil }
            return value
        } catch is CancellationError {
            if isReauthentication { clearPasswords(ifCurrent: originalDraft) }
            return nil
        }
        catch {
            if isReauthentication { clearPasswords(ifCurrent: originalDraft) }
            guard admission == event, active == nil else { return nil }
            errorMessage = message(for: error)
            return nil
        }
    }

    func submit(_ submission: Submission) async {
        guard active?.id == submission.id, cancelledID != submission.id, performingID == nil else { return }
        if isReauthentication && Task.isCancelled { cancel(); return }
        performingID = submission.id
        defer {
            if performingID == submission.id { performingID = nil }
            if active?.id == submission.id { active = nil; objectWillChange.send() }
        }
        do {
            let result = try await submission.operation.perform()
            guard owns(submission) else { return }
            if isReauthentication { return } // Identity confirmation is not login or a new session.
            if submission.action == .resetPassword {
                statusMessage = "Hvis adressen har en konto, modtager du en mail med hjælp til at vælge en ny adgangskode."
            } else {
                authenticatedSession = result
                guard owns(submission) else { return }
                clearPasswords()
            }
        } catch is CancellationError { }
        catch {
            guard owns(submission) else { return }
            errorMessage = message(for: error)
        }
    }

    /// Kept for hermetic callers. Production buttons always capture before Task.
    func submit() async { if let submission = captureSubmission() { await submit(submission) } }

    func cancel() {
        admission = UUID()
        guard let original = active, cancelledID != original.id else {
            if isReauthentication, active == nil { clearPasswords(ifCurrent: draftRevision) }
            return
        }
        let originalDraft = draftRevision
        cancelledID = original.id
        original.operation.cancel()
        if isReauthentication { clearPasswords(ifCurrent: originalDraft) } else { clearPasswords() }
        if performingID != original.id, active?.id == original.id { active = nil }
        objectWillChange.send()
    }
    func clearPasswords() {
        // Publish the whole cleared draft once. An observer can replace the
        // draft during publication; no tail write may alter that replacement.
        var cleared = form
        cleared.password = ""; cleared.confirmation = ""
        form = cleared
    }
    private func clearPasswords(ifCurrent revision: UUID) {
        guard draftRevision == revision, !form.password.isEmpty || !form.confirmation.isEmpty else { return }
        clearPasswords()
    }
    private func message(for error: Error) -> String {
        if isReauthentication { return "Kunne ikke bekræfte din identitet. Prøv igen." }
        return (error as? AuthOperationCoordinator.Failure)?.message ?? AccountErrorMessage.forError(error)
    }
    private func owns(_ original: Submission) -> Bool {
        guard active?.id == original.id, cancelledID != original.id else { return false }
        let permitted = original.operation.feedbackIsCurrent()
        return permitted && active?.id == original.id && cancelledID != original.id
    }
}
