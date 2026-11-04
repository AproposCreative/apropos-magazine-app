import AuthenticationServices
import SwiftUI

/// Native Apple artwork and button semantics. This entry control performs no
/// authentication: its parent first completes the owner-bound modal handoff.
struct ReaderIntroductionAppleButton: UIViewRepresentable {
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.locale) private var locale

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .white)
        button.cornerRadius = 12
        button.accessibilityIdentifier = "introduction.account.apple"
        button.accessibilityLabel = AppLocalization.string("Fortsæt med Apple", language: AppLocalization.language(for: locale))
        button.addTarget(context.coordinator, action: #selector(Coordinator.invoke), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = isEnabled
        button.accessibilityLabel = AppLocalization.string("Fortsæt med Apple", language: AppLocalization.language(for: locale))
    }

    static func dismantleUIView(_ button: ASAuthorizationAppleIDButton, coordinator: Coordinator) {
        button.removeTarget(coordinator, action: #selector(Coordinator.invoke), for: .touchUpInside)
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func invoke() { action() }
    }
}
