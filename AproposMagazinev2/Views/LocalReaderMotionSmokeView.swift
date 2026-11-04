#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import FirebaseCore

/// Real WebKit renderer/viewport bridge with local prose and no service adapters.
struct LocalReaderMotionSmokeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var motion = ArticleReadingMotionController()
    @State private var height: CGFloat = 240
    @State private var ready = false
    @State private var horizontalOverflow: Bool?
    @State private var reduced = false
    private static let prose = """
    <p>En god artikel giver plads til at tænke. Ordene står roligt på siden, mens byen fortsætter udenfor.</p>
    <h2>Plads til fortællingen</h2>
    <p>Vi møder musikken med nysgerrighed. Det er detaljerne mellem de store øjeblikke, der gør en oplevelse værd at dele.</p>
    """ + (1...12).map { index in
        "<p>Afsnit \(index). Stemmerne i salen bliver stille. Her er der tid til at læse videre, følge en tanke og vende tilbage til det, der fortjener et ekstra blik. Fortællingen skal kunne læses i eget tempo, uden at indholdet flytter sig under fingeren.</p>"
    }.joined() + "<h2>Til sidst</h2><p>Her slutter artikelteksten. Anbefalingerne nedenunder tæller ikke med i læsefremdriften.</p>"

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "chevron.left")
                    Spacer()
                    Image(colorScheme == .dark ? "AproposLogoWhite" : "AproposLogoBlack").resizable().scaledToFit().frame(height: 25)
                    Spacer()
                    Image(systemName: "square.and.arrow.up")
                }
                .padding(.horizontal, 20)
                Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase startet")
                    .font(.caption).accessibilityIdentifier("motion.firebase")
                Toggle("Reducer bevægelse i testen", isOn: $reduced).font(.caption)
                    .accessibilityIdentifier("motion.reduced")
                    .padding(.horizontal, 20)
            }
            .padding(.vertical, 10)
            .dynamicTypeSize(.large)
            .overlay(alignment: .bottom) {
                ArticleReadingProgressLine(controller: motion).frame(height: 1.5)
            }
            .background(Color(uiColor: .systemBackground))
            .zIndex(1)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Tid til at læse").font(.largeTitle.bold()).padding(.horizontal, 16)
                    Text("Lokal artikel med den samme læselinje og HTML-renderer som appen.")
                        .font(.title3).padding(.horizontal, 16)
                    Rectangle().fill(.primary.opacity(0.05)).frame(height: 120)
                        .overlay(Image(systemName: "text.book.closed").font(.largeTitle).foregroundStyle(.secondary))
                    HTMLTextView(html: Self.prose, articleId: "local-motion-fixture", dynamicHeight: $height,
                                 readingMotion: motion, suppressMotion: reduced, onReadingProgress: { _ in if !ready { ready = true } },
                                 onHorizontalOverflow: { if horizontalOverflow != $0 { horizontalOverflow = $0 } },
                                 prepareHTML: { html, _ in .init(html: html, baseURL: nil) })
                        .frame(height: max(height, 240))
                    Text("Læs også · lokal test").font(.title2.bold()).padding(.horizontal, 16)
                    Text("Artiklen er slut. Linjen skal blive på 100 procent her.")
                        .padding(.horizontal, 16)
                    Color.clear.frame(height: 650)
                }
            }
            .clipped()
            .accessibilityIdentifier("motion.scroll")
        }
        .foregroundStyle(Color.primary)
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing) {
                if ready { Text("Artikel klar").accessibilityIdentifier("motion.ready") }
                if let horizontalOverflow {
                    Text(horizontalOverflow ? "FEJL: vandret tekstoverflow" : "Tekstombrydning: ok")
                }
            }
            .padding(4).font(Font.system(size: 11)).background(Color(uiColor: .systemBackground))
        }
    }
}
#endif
