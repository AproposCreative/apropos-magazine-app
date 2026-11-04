import SwiftUI
import MessageUI

/// A fresh in-memory draft belongs to this contact window, without account data.
struct ContactUsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = SupportContactRuntime.makeModel()

    var body: some View {
        NavigationStack {
            Form { SupportContactSections(model: model) }
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle("Kontakt os")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Færdig") {
                            model.invalidateContext()
                            dismiss()
                        }
                        .tint(.primary)
                    }
                }
        }
        .sheet(item: Binding(get: { model.presentation }, set: { value in
            if value == nil, let id = model.presentation?.id { model.composerDismissed(id: id) }
        })) { draft in
            SupportMailComposer(draft: draft) { result in
                model.finishComposer(id: draft.id, result: result)
            }
        }
    }
}

@MainActor
private enum SupportContactRuntime {
    static var isDisabled: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || LocalSmokeMode.isEnabled
    }

    static func makeModel() -> SupportContactModel {
        let disabled = isDisabled
        return SupportContactModel(canCompose: { !disabled && MFMailComposeViewController.canSendMail() }, openURL: { url, completion in
            guard !disabled else { completion(false); return }
            UIApplication.shared.open(url, options: [:]) { accepted in
                Task { @MainActor in completion(accepted) }
            }
        }, copy: { text in
            guard !disabled else { return false }
            UIPasteboard.general.string = text
            return UIPasteboard.general.string == text
        }, schedule: { seconds, action in
            guard !disabled else { return {} }
            let task = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
                catch { return }
                guard !Task.isCancelled else { return }
                action()
            }
            return { task.cancel() }
        })
    }
}

/// Platform UI is constructed only after a deliberate user action. There is no
/// send API call here; Mail owns the user's Send/Save/Cancel interaction.
private struct SupportMailComposer: UIViewControllerRepresentable {
    let draft: SupportContactModel.ComposerDraft
    let onFinish: @MainActor (SupportContactModel.ComposerResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIViewController {
        guard !SupportContactRuntime.isDisabled,
              draft.recipient == SupportContactPolicy.recipient,
              draft.subject == SupportContactPolicy.subject,
              SupportContactPolicy.canPresentComposer(body: draft.body),
              MFMailComposeViewController.canSendMail() else {
            Task { @MainActor in onFinish(.failed) }
            return UIViewController()
        }
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setToRecipients([draft.recipient])
        composer.setSubject(draft.subject)
        composer.setMessageBody(draft.body, isHTML: false)
        return composer
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: UIViewController, coordinator: Coordinator) {
        (controller as? MFMailComposeViewController)?.mailComposeDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private var finished = false
        private let onFinish: @MainActor (SupportContactModel.ComposerResult) -> Void
        init(onFinish: @escaping @MainActor (SupportContactModel.ComposerResult) -> Void) { self.onFinish = onFinish }
        nonisolated func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            let outcome: SupportContactModel.ComposerResult
            if error != nil { outcome = .failed }
            else {
                switch result {
                case .sent: outcome = .sent
                case .saved: outcome = .saved
                case .cancelled: outcome = .cancelled
                case .failed: outcome = .failed
                @unknown default: outcome = .failed
                }
            }
            // Project to a Sendable value before crossing to the UI actor;
            // neither the Mail controller nor its Error is retained by the task.
            Task { @MainActor [weak self] in self?.complete(outcome) }
        }

        private func complete(_ outcome: SupportContactModel.ComposerResult) {
            guard !finished else { return }
            finished = true
            onFinish(outcome)
        }
    }
}
