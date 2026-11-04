import Combine
import Foundation

/// Each renderer keeps its original history session and document nonce. Merely
/// loading or measuring a document cannot replace a saved reading position.
@MainActor
final class ReaderResumeController: ObservableObject {
    struct Snapshot: Equatable {
        var offer: ReaderResumeAnchor?
        var message: String?
        var isResuming = false
    }
    private struct Binding {
        let token: UUID
        let owner: String
        let source: ReaderResumeIdentity
        let sessionID: UUID
        let documentID: String
        let isCurrent: @MainActor () -> Bool
    }
    nonisolated let objectWillChange = ObservableObjectPublisher()
    private var committedSnapshot = Snapshot()
    private var snapshotAuthority: UUID?
    var snapshot: Snapshot {
        guard let original = binding, snapshotAuthority == original.token, owns(original) else { return Snapshot() }
        return committedSnapshot
    }
    private let store: ReaderResumeStore
    private let disabled: Bool
    private let legacyAdmission: ReaderLegacyWriteAdmission?
    private var binding: Binding?
    private var deniedBinding: UUID?
    private var loadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var saveRevision = UUID()
    private var lastSample: ReaderResumeAnchor?
    private var hasSample = false
    private var userInteracted = false
    private var admission = UUID()
    private var publication = UUID()
    private var resumeRequest: UUID?
    private static let resumeFailureMessage = "Læsepositionen kunne ikke findes i denne visning. Du kan fortsat læse fra starten."

    init(store: ReaderResumeStore, disabled: Bool = false, legacyAdmission: ReaderLegacyWriteAdmission? = nil) {
        self.store = store; self.disabled = disabled; self.legacyAdmission = legacyAdmission
    }

    func bind(owner: String, source: ReaderResumeIdentity, sessionID: UUID, documentID: String,
              isCurrent: @escaping @MainActor () -> Bool) {
        let previous = binding
        let sameSession = previous?.owner == owner && previous?.source == source && previous?.sessionID == sessionID
        let attempt = UUID(); admission = attempt
        guard !disabled, legacyAdmission?.isAllowed ?? true, ReaderResumeRecord.validOwner(owner), source.isValid,
              UUID(uuidString: documentID) != nil else { invalidate(); return }
        let permitted = isCurrent()
        guard admission == attempt else { return }
        guard permitted, legacyAdmission?.isAllowed ?? true else { invalidate(); return }
        loadTask?.cancel(); saveTask?.cancel(); saveRevision = UUID()
        let next = Binding(token: UUID(), owner: owner, source: source, sessionID: sessionID,
                           documentID: documentID, isCurrent: isCurrent)
        binding = next; deniedBinding = nil
        snapshotAuthority = nil; publication = UUID(); resumeRequest = nil
        if !sameSession { userInteracted = false }
        hasSample = false; lastSample = nil
        // Defer publication out of UIViewRepresentable.updateUIView.
        loadTask = Task { @MainActor [weak self] in
            guard let self, self.owns(next) else { return }
            guard self.publish(Snapshot(), for: next) else { return }
            do {
                guard self.admits(next) else { return }
                let saved = try await self.store.load(owner: owner, source: source)
                guard !Task.isCancelled, self.owns(next), !self.userInteracted else { return }
                _ = self.publish(Snapshot(offer: saved), for: next)
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled, self.owns(next) else { return }
                _ = self.publish(Snapshot(message: "Din læseposition kunne ikke indlæses. Du kan fortsat læse fra starten."), for: next)
            }
        }
    }

    func invalidate(documentID: String? = nil) {
        if let documentID, binding?.documentID != documentID { return }
        admission = UUID(); publication = UUID(); snapshotAuthority = nil; resumeRequest = nil
        binding = nil; deniedBinding = nil; loadTask?.cancel(); saveTask?.cancel(); saveRevision = UUID()
        Task { @MainActor [weak self] in
            guard let self, self.binding == nil else { return }
            let operation = UUID(); self.publication = operation
            self.objectWillChange.send()
            guard self.binding == nil, self.publication == operation else { return }
            self.committedSnapshot = Snapshot()
        }
    }

    /// Called only by the native viewport bridge after a genuine scroll settles.
    func record(_ anchor: ReaderResumeAnchor, completed: Bool, documentID: String) {
        guard let original = binding, original.documentID == documentID, owns(original), anchor.isValid else { return }
        userInteracted = true
        let desired = completed || anchor.index == 0 ? nil : anchor
        guard !hasSample || desired != lastSample else { return }
        hasSample = true; lastSample = desired
        // Supersede only the older UI receipt, including when this admission
        // fails. Its later success must not erase the latest save failure.
        saveTask?.cancel()
        let revision = UUID(); saveRevision = revision
        let receipt: ReaderResumeStore.Receipt
        do {
            // Admit the immutable owner/source value synchronously. Closing or
            // rebinding may discard UI feedback, but cannot cancel this write.
            guard admits(original), saveRevision == revision else { return }
            receipt = try store.accept(owner: original.owner, source: original.source, anchor: desired)
        } catch {
            guard owns(original) else { return }
            hasSample = false
            var next = snapshot
            next.message = "Din læseposition kunne ikke gemmes på denne enhed. Prøv at læse videre, når lageret er tilgængeligt."
            _ = publish(next, for: original)
            return
        }
        saveTask = Task { @MainActor [weak self] in
            do {
                try await receipt.value()
                guard !Task.isCancelled, let self, self.owns(original), self.saveRevision == revision else { return }
                // Keep the original offer's layout stable while reading. It is
                // refreshed from storage when the reader is opened again.
                if self.snapshot.message != nil {
                    var next = self.snapshot; next.message = nil; _ = self.publish(next, for: original)
                }
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled, let self, self.owns(original), self.saveRevision == revision else { return }
                self.hasSample = false
                var next = self.snapshot
                next.message = "Din læseposition kunne ikke gemmes på denne enhed. Prøv at læse videre, når lageret er tilgængeligt."
                _ = self.publish(next, for: original)
            }
        }
    }

    func resume(using perform: (ReaderResumeAnchor, String, @escaping @MainActor () -> Bool,
                               @escaping @MainActor (Bool) -> Void) -> Void) {
        guard let original = binding, owns(original), let anchor = snapshot.offer,
              !snapshot.isResuming else { return }
        let request = UUID(); resumeRequest = request
        var next = snapshot; next.isResuming = true
        guard publish(next, for: original), owns(original), resumeRequest == request else { return }
        perform(anchor, original.documentID, { [weak self] in self?.owns(original) ?? false }) { [weak self] success in
            guard let self, self.owns(original), self.resumeRequest == request else { return }
            self.resumeRequest = nil
            var next = self.snapshot; next.isResuming = false
            if !success { next.message = ReaderResumeController.resumeFailureMessage }
            else if next.message == ReaderResumeController.resumeFailureMessage { next.message = nil }
            _ = self.publish(next, for: original)
        }
    }

    func waitForPendingWork() async { await loadTask?.value; await saveTask?.value }
    /// Pure last-effect check. A denial observed by this binding stays denied
    /// even if a later local startup decision reopens admission; only an
    /// explicit fresh bind may capture a new document/session.
    private func admits(_ proposed: Binding) -> Bool {
        guard binding?.token == proposed.token, deniedBinding != proposed.token else { return false }
        guard legacyAdmission?.isAllowed ?? true else { deniedBinding = proposed.token; return false }
        return true
    }
    private func owns(_ proposed: Binding) -> Bool {
        guard admits(proposed) else { return false }
        let permitted = proposed.isCurrent()
        return admits(proposed) && permitted
    }
    @discardableResult private func publish(_ proposed: Snapshot, for original: Binding) -> Bool {
        guard owns(original) else { return false }
        let operation = UUID(); publication = operation
        objectWillChange.send()
        guard publication == operation, owns(original), publication == operation, admits(original) else { return false }
        committedSnapshot = proposed; snapshotAuthority = original.token
        return true
    }
}
