import SwiftUI

/// Shared production/fixture feedback. The presented item owns its original ID:
/// a late native dismissal cannot clear a newer route's identical message.
struct IncomingLinkFeedback: ViewModifier {
    let message: String?
    let messageID: UUID?
    let dismiss: (UUID) -> Void

    private struct Presentation: Identifiable {
        let id: UUID
        let message: String
    }

    func body(content: Content) -> some View {
        content.alert(item: Binding<Presentation?>(get: {
            guard let message, let messageID else { return nil }
            return Presentation(id: messageID, message: message)
        }, set: { _ in
            // SwiftUI can set an older presentation binding to nil after a new
            // item exists. Only the button's captured item can acknowledge it.
        })) { original in
            Alert(title: Text("Dit link"), message: Text(LocalizedStringKey(original.message)),
                  dismissButton: .cancel(Text("Luk"), action: { dismiss(original.id) }))
        }
    }
}

extension View {
    func incomingLinkFeedback(message: String?, messageID: UUID?, dismiss: @escaping (UUID) -> Void) -> some View {
        modifier(IncomingLinkFeedback(message: message, messageID: messageID, dismiss: dismiss))
    }
}
