import SwiftUI

struct ReaderResumeNotice: View {
    @ObservedObject var controller: ReaderResumeController
    let motion: ArticleReadingMotionController
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if controller.snapshot.offer != nil {
                Button {
                    controller.resume { anchor, documentID, permitted, completion in
                        motion.resume(anchor: anchor, documentID: documentID, stillCurrent: permitted, completion: completion)
                    }
                } label: {
                    Label("Fortsæt læsning", systemImage: "text.book.closed")
                        .font(.subheadline.weight(.medium))
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(controller.snapshot.isResuming)
                .accessibilityHint("Gå til det afsnit, du sidst læste på denne enhed.")
                .accessibilityIdentifier("reader.resume")
            }
            if let message = controller.snapshot.message {
                Text(LocalizedStringKey(message)).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("reader.resume.message")
            }
        }
    }
}
