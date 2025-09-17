import SwiftUI

// MARK: - Readability Settings

struct ReadabilitySettings {
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let paragraphSpacing: CGFloat
    let letterSpacing: CGFloat
    let maxLineWidth: CGFloat
    let backgroundColor: Color
    let textColor: Color
    
    static let optimal = ReadabilitySettings(
        fontSize: 18,
        lineHeight: 1.6,
        paragraphSpacing: 24,
        letterSpacing: 0.2,
        maxLineWidth: 600,
        backgroundColor: Color(.systemBackground),
        textColor: Color(.label)
    )
    
    static let large = ReadabilitySettings(
        fontSize: 20,
        lineHeight: 1.7,
        paragraphSpacing: 28,
        letterSpacing: 0.3,
        maxLineWidth: 650,
        backgroundColor: Color(.systemBackground),
        textColor: Color(.label)
    )
    
    static let compact = ReadabilitySettings(
        fontSize: 16,
        lineHeight: 1.5,
        paragraphSpacing: 20,
        letterSpacing: 0.1,
        maxLineWidth: 550,
        backgroundColor: Color(.systemBackground),
        textColor: Color(.label)
    )
    
    static let night = ReadabilitySettings(
        fontSize: 18,
        lineHeight: 1.6,
        paragraphSpacing: 24,
        letterSpacing: 0.2,
        maxLineWidth: 600,
        backgroundColor: Color.black,
        textColor: Color.white
    )
}

// MARK: - Readable Text View

struct ReadableTextView: View {
    let text: String
    let settings: ReadabilitySettings
    let showReadingProgress: Bool
    
    @State private var readingProgress: Double = 0.0
    @State private var estimatedReadingTime: Int = 0
    
    init(
        text: String,
        settings: ReadabilitySettings = .optimal,
        showReadingProgress: Bool = true
    ) {
        self.text = text
        self.settings = settings
        self.showReadingProgress = showReadingProgress
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showReadingProgress {
                readingProgressView
                    .padding(.bottom, 16)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: settings.paragraphSpacing) {
                    ForEach(paragraphs, id: \.self) { paragraph in
                        Text(paragraph)
                            .font(.system(size: settings.fontSize, weight: .regular, design: .serif))
                            .lineSpacing(settings.lineHeight - 1.0)
                            .tracking(settings.letterSpacing)
                            .foregroundColor(settings.textColor)
                            .frame(maxWidth: settings.maxLineWidth, alignment: .leading)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .preference(key: ScrollOffsetKey.self, value: geometry.frame(in: .named("readableScroll")).minY)
                    }
                )
            }
            .coordinateSpace(name: "readableScroll")
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                updateReadingProgress(offset: offset)
            }
        }
        .background(settings.backgroundColor)
        .onAppear {
            calculateReadingTime()
        }
    }
    
    private var paragraphs: [String] {
        text.components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    
    private var readingProgressView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Læseprogression")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(Int(readingProgress * 100))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: readingProgress)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                .scaleEffect(y: 2)
        }
        .padding(.horizontal, 20)
    }
    
    private func updateReadingProgress(offset: CGFloat) {
        // Calculate reading progress based on scroll position
        // This is a simplified calculation
        let progress = max(0, min(1, -offset / 1000))
        readingProgress = progress
    }
    
    private func calculateReadingTime() {
        // Average reading speed: 200 words per minute
        let words = text.components(separatedBy: .whitespaces).count
        estimatedReadingTime = max(1, words / 200)
    }
}

// MARK: - Article Content View

struct ArticleContentView: View {
    let article: Article
    @ObservedObject private var preferencesManager = PreferencesManager.shared
    @State private var currentSettings: ReadabilitySettings = .optimal
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Article Header
            articleHeaderView
            
            // Reading Settings
            readingSettingsView
            
            // Article Content
            ReadableTextView(
                text: article.content ?? "",
                settings: currentSettings,
                showReadingProgress: true
            )
        }
        .background(currentSettings.backgroundColor)
        .onAppear {
            updateReadabilitySettings()
        }
        .onChange(of: preferencesManager.preferences.readingPreferences) { _, _ in
            updateReadabilitySettings()
        }
    }
    
    private var articleHeaderView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            Text(article.name ?? "")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .lineSpacing(1.2)
                .foregroundColor(currentSettings.textColor)
                .padding(.horizontal, 20)
                .padding(.top, 24)
            
            // Meta information
            HStack {
                if let authorId = article.authorID {
                    Text("Af \(authorId)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let stjerne = article.stjerne {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                        Text("\(stjerne)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            
            Divider()
                .padding(.horizontal, 20)
        }
    }
    
    private var readingSettingsView: some View {
        HStack {
            Button(action: {
                cycleReadabilitySettings()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "textformat.size")
                    Text("Læsning")
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            Spacer()
            
            Button(action: {
                toggleReadingMode()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "moon")
                    Text("Nattilstand")
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
    }
    
    private func updateReadabilitySettings() {
        let readingPrefs = preferencesManager.preferences.readingPreferences
        
        // Apply font size
        var fontSize: CGFloat = 18
        switch readingPrefs.fontSize {
        case .small: fontSize = 16
        case .medium: fontSize = 18
        case .large: fontSize = 20
        case .extraLarge: fontSize = 22
        }
        
        // Apply line spacing
        var lineHeight: CGFloat = 1.6
        switch readingPrefs.lineSpacing {
        case .tight: lineHeight = 1.3
        case .normal: lineHeight = 1.5
        case .comfortable: lineHeight = 1.7
        case .relaxed: lineHeight = 1.9
        }
        
        // Apply reading mode
        var backgroundColor = Color(.systemBackground)
        var textColor = Color(.label)
        
        switch readingPrefs.readingMode {
        case .default:
            backgroundColor = Color(.systemBackground)
            textColor = Color(.label)
        case .focus:
            backgroundColor = Color(.systemGray6)
            textColor = Color(.label)
        case .distractionFree:
            backgroundColor = Color(.systemBackground)
            textColor = Color(.label)
        case .night:
            backgroundColor = Color.black
            textColor = Color.white
        }
        
        currentSettings = ReadabilitySettings(
            fontSize: fontSize,
            lineHeight: lineHeight,
            paragraphSpacing: 24,
            letterSpacing: 0.2,
            maxLineWidth: 600,
            backgroundColor: backgroundColor,
            textColor: textColor
        )
    }
    
    private func cycleReadabilitySettings() {
        // Cycle through different readability presets
        switch currentSettings.fontSize {
        case 16:
            currentSettings = .optimal
        case 18:
            currentSettings = .large
        case 20:
            currentSettings = .compact
        default:
            currentSettings = .optimal
        }
        
        HapticManager.shared.selection()
    }
    
    private func toggleReadingMode() {
        if currentSettings.backgroundColor == Color.black {
            currentSettings = .optimal
        } else {
            currentSettings = .night
        }
        
        HapticManager.shared.mediumImpact()
    }
}

// MARK: - Typography Extensions

extension View {
    func optimalLineHeight() -> some View {
        self.lineSpacing(1.6)
    }
    
    func comfortableLineHeight() -> some View {
        self.lineSpacing(1.7)
    }
    
    func relaxedLineHeight() -> some View {
        self.lineSpacing(1.8)
    }
    
    func serifFont() -> some View {
        self.font(.system(.body, design: .serif))
    }
    
    func readableText() -> some View {
        self
            .font(.system(.body, design: .serif))
            .lineSpacing(1.6)
            .tracking(0.2)
    }
    
    func readableTitle() -> some View {
        self
            .font(.system(size: 28, weight: .bold, design: .serif))
            .lineSpacing(1.2)
            .tracking(0.1)
    }
}

// MARK: - Reading Time Calculator

struct ReadingTimeCalculator {
    static func calculateReadingTime(for text: String) -> Int {
        let words = text.components(separatedBy: .whitespaces).count
        let averageWPM = 200 // Average reading speed
        return max(1, words / averageWPM)
    }
    
    static func formatReadingTime(_ minutes: Int) -> String {
        if minutes < 1 {
            return "Mindre end 1 minut"
        } else if minutes == 1 {
            return "1 minut"
        } else {
            return "\(minutes) minutter"
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleArticle = Article(
        id: "1",
        name: "Justice (O Days Festival): Total forløsning i mudder og bassdrops",
        slug: "justice-o-days-festival",
        content: """
        Lørdagen blev reddet af to franske prædikanter med bassdrops i stedet for bibelvers.
        
        Justice's optræden på O Days Festival var en total forløsning efter en dag fyldt med regn og mudder. Duoen fra Paris leverede en masterclass i elektronisk musik, der fik hele publikum til at glemme de våde omstændigheder.
        
        Fra det første øjeblik de trådte på scenen, var det tydeligt, at dette ville blive noget særligt. Deres karakteristiske blend af house, disco og elektronisk musik skabte en atmosfære af ren eufori. Bassdropsne var massive, men aldrig overvældende - hver enkelt var perfekt timet og produceret.
        
        Publikum reagerede med samme intensitet som musikken. Der var ingen der stod stille, selv ikke i de dybeste mudderpøle. Justice's evne til at bygge og frigive spænding var helt enestående - hver overgang føltes naturlig og uundgåelig.
        
        Det var ikke bare en koncert, det var en oplevelse der vil blive husket længe efter festivalen er slut.
        """,
        intro: "Lørdagen blev reddet af to franske prædikanter med bassdrops i stedet for bibelvers.",
        stjerne: 4,
        topicID: "Festival",
        topicsIDs: ["Festival", "Musik"],
        authorID: "Frederik Emil",
        thumbURL: URL(string: "https://picsum.photos/400/300")!,
        coverURL: nil,
        location: "Odense",
        subtitle: nil,
        isDraft: nil
    )
    
    ArticleContentView(article: sampleArticle)
}
