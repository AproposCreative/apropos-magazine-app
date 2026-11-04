import SwiftUI

/// SwiftUI's onAppear may run while a sheet is still being presented. This
/// SDK-free bridge waits for UIKit's completed appearance before one handoff.
struct AccountEntryActivation: UIViewControllerRepresentable {
    let onReady: () -> Void

    func makeUIViewController(context: Context) -> Controller { Controller(onReady: onReady) }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onReady = onReady
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.invalidate()
    }

    final class Controller: UIViewController {
        var onReady: () -> Void
        private var fired = false
        private var invalidated = false

        init(onReady: @escaping () -> Void) {
            self.onReady = onReady
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func loadView() {
            let view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            view.accessibilityElementsHidden = true
            self.view = view
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !fired, !invalidated, view.window != nil else { return }
            fired = true
            onReady()
        }

        func invalidate() { invalidated = true; onReady = {} }
    }
}
