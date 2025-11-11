import SwiftUI

struct WhatsNewView: View {
    let entries: [WhatsNewEntry]
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var backgroundGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(.sRGB, red: 0.08, green: 0.09, blue: 0.12, opacity: 1),
                    Color(.sRGB, red: 0.05, green: 0.05, blue: 0.07, opacity: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [
                Color(.sRGB, red: 0.96, green: 0.97, blue: 1, opacity: 1),
                Color(.sRGB, red: 0.95, green: 0.95, blue: 0.98, opacity: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var sortedEntries: [WhatsNewEntry] {
        entries.sorted { entry1, entry2 in
            // Sort by version (newest first)
            let version1 = entry1.version.split(separator: ".").compactMap { Int($0) }
            let version2 = entry2.version.split(separator: ".").compactMap { Int($0) }
            let maxCount = max(version1.count, version2.count)
            
            for index in 0..<maxCount {
                let v1 = index < version1.count ? version1[index] : 0
                let v2 = index < version2.count ? version2[index] : 0
                if v1 > v2 { return true }
                if v1 < v2 { return false }
            }
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Text("Velkommen til Apropos Magazine")
                    .font(.system(.largeTitle, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                
                Text("Her er alle de nye features og forbedringer")
                    .font(.system(.subheadline, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
            }
            .padding(.top, 48)
            .padding(.bottom, 24)

            ScrollView {
                VStack(spacing: 32) {
                    ForEach(sortedEntries) { entry in
                        WhatsNewVersionSection(entry: entry)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            Button(action: onDismiss) {
                Text("Fortsæt")
                    .font(.system(.headline, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(colorScheme == .dark ? Color.white : Color.blue)
                    .foregroundColor(colorScheme == .dark ? Color.black : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundGradient.ignoresSafeArea())
    }
}

private struct WhatsNewVersionSection: View {
    let entry: WhatsNewEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Version header
            VStack(alignment: .leading, spacing: 4) {
                Text("Version \(entry.version)")
                    .font(.system(.title2, weight: .bold))
                
                if let subtitle = entry.subtitle {
                    Text(subtitle)
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 8)
            
            // Items
            VStack(spacing: 20) {
                ForEach(entry.items) { item in
                    WhatsNewRow(item: item)
                }
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.6))
        )
    }
}

private struct WhatsNewRow: View {
    let item: WhatsNewItem

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: item.icon)
                .font(.system(size: 26, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.15))
                .foregroundStyle(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(.headline, weight: .semibold))
                    .multilineTextAlignment(.leading)

                Text(item.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    let entries = [
        WhatsNewEntry(
            version: "2.3.0",
            title: "Nyheder i Apropos Magazine",
            subtitle: "En hurtigere, mere elegant app-oplevelse med fokus på læsning.",
            items: [
                WhatsNewItem(icon: "sparkles", title: "Forbedret artikelsøgning", description: "Filtrer på kategorier og se relaterede artikler direkte i søgeresultaterne."),
                WhatsNewItem(icon: "bolt.circle", title: "Mere stabile notifikationer", description: "Vi har optimeret push-motoren, så du kun får de beskeder, der betyder noget."),
                WhatsNewItem(icon: "wand.and.stars", title: "Glas topbar", description: "Appen har fået et visuelt løft med en ny glas-topbar, der gør navigationen elegant.")
            ],
            ctaTitle: nil,
            ctaURL: nil
        ),
        WhatsNewEntry(
            version: "1.0",
            title: "Velkommen til Apropos Magazine",
            subtitle: "Din nye app til at læse og opdage artikler fra Apropos Magazine.",
            items: [
                WhatsNewItem(icon: "sparkles", title: "Forbedret artikelsøgning", description: "Filtrer på kategorier og se relaterede artikler direkte i søgeresultaterne."),
                WhatsNewItem(icon: "bolt.circle", title: "Mere stabile notifikationer", description: "Vi har optimeret push-motoren, så du kun får de beskeder, der betyder noget.")
            ],
            ctaTitle: nil,
            ctaURL: nil
        )
    ]
    WhatsNewView(entries: entries, onDismiss: {})
}
