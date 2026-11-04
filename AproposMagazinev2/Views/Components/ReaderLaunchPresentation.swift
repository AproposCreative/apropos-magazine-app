import SwiftUI

/// Shared by the actual app and the local introduction fixture.
struct ReaderLaunchPresentation: ViewModifier {
    @ObservedObject var coordinator: ReaderLaunchCoordinator
    let introduction: () -> AnyView
    let whatsNew: () -> AnyView
    let account: (ReaderAccountEntry) -> AnyView
    let newsletter: () -> AnyView

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: Binding(get: { coordinator.cover }, set: {
                if $0 == nil { coordinator.dismissCover() }
            }), onDismiss: { coordinator.coverDidDismiss() }) { _ in
                introduction()
            }
            .sheet(item: Binding(get: { coordinator.sheet }, set: {
                if $0 == nil { coordinator.dismissSheet() }
            }), onDismiss: { coordinator.sheetDidDismiss() }) { presentation in
                switch presentation.kind {
                case .whatsNew: whatsNew()
                case .account: account(presentation.accountEntry)
                case .newsletter: newsletter()
                case .introduction: EmptyView()
                }
            }
    }
}
