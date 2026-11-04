import Combine
import Foundation

/// Memory-only checkbox state. Consent belongs to the exact account context in
/// which it was chosen; observing a replacement context can only clear it.
@MainActor
final class ReaderNewsletterOptInDraft: ObservableObject {
    nonisolated let objectWillChange = ObservableObjectPublisher()
    private weak var canonical: CanonicalSessionState?
    private let initialContext: CanonicalSessionState.ContextTicket
    private var context: CanonicalSessionState.ContextTicket
    private var choice: Bool
    private var initialEntryConsumed = false
    private var initialEntryRevoked = false
    private var observation: AnyCancellable?
    private var notifying = false

    init(canonical: CanonicalSessionState, selected: Bool = false) {
        self.canonical = canonical
        let original = canonical.contextTicket()
        initialContext = original
        context = original
        choice = selected && original.context != .unresolved
        observation = canonical.changes.sink { [weak self] _ in self?.adoptCurrentContext() }
    }

    var selected: Bool { isSelected(for: context) }

    /// Reads validate synchronously too: another canonical observer may run
    /// before this draft's subscriber, and no render is needed to revoke consent.
    func isSelected(for original: CanonicalSessionState.ContextTicket) -> Bool {
        choice && original == context && original.context != .unresolved && canonical?.isCurrent(original) == true
    }

    @discardableResult
    func setSelected(_ selected: Bool, context original: CanonicalSessionState.ContextTicket) -> Bool {
        guard original == context, original.context != .unresolved, canonical?.isCurrent(original) == true else { return false }
        guard choice != selected else { return true }
        choice = selected
        publish()
        return canonical?.isCurrent(original) == true
    }

    /// Used again at the provider's actual start, after any UIKit scheduling hop.
    var initialEntryIsCurrent: Bool {
        !initialEntryRevoked && initialContext.context != .unresolved && canonical?.isCurrent(initialContext) == true
    }

    /// The presentation completion may use the original entry once. A later
    /// account cannot inherit that action, even if the user manually opts in anew.
    func consumeInitialEntryContext() -> CanonicalSessionState.ContextTicket? {
        guard !initialEntryConsumed else { return nil }
        initialEntryConsumed = true
        return initialEntryIsCurrent ? initialContext : nil
    }

    private func adoptCurrentContext() {
        guard let canonical else { return }
        let current = canonical.contextTicket()
        guard current != context else { return }
        context = current
        choice = false
        initialEntryRevoked = true
        publish()
    }

    private func publish() {
        // State is already committed. Reentrant observers cannot restore an old
        // choice after a nested account change completes.
        guard !notifying else { return }
        notifying = true
        objectWillChange.send()
        notifying = false
    }
}
