import SwiftUI

/// Subtle, App Store-compliant disclosure that an episode is an AI-generated
/// narration rather than a human-recorded podcast. Keeps the "Podcast" branding
/// intact while making the AI origin clear ("Oplæst med AI").
struct AINarrationBadge: View {
    enum Style {
        /// Compact pill used in tight spaces (mini-player, cards).
        case compact
        /// Slightly larger pill used in the full player.
        case prominent
    }

    var style: Style = .compact

    private var fontSize: CGFloat {
        style == .prominent ? 12 : 10
    }

    private var horizontalPadding: CGFloat {
        style == .prominent ? 8 : 6
    }

    private var verticalPadding: CGFloat {
        style == .prominent ? 4 : 2
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: fontSize, weight: .semibold))
            Text("Oplæst med AI")
                .font(.system(size: fontSize, weight: .semibold))
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .foregroundStyle(.secondary)
        .background(
            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(0.14))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Oplæst med kunstig intelligens")
    }
}

#Preview {
    VStack(spacing: 12) {
        AINarrationBadge(style: .compact)
        AINarrationBadge(style: .prominent)
    }
    .padding()
}
