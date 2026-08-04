import SwiftUI

struct NotificationOnboardingView: View {
    @ObservedObject private var notificationService = NotificationService.shared
    @EnvironmentObject private var viewModel: ArticleViewModel
    @Environment(\.colorScheme) private var colorScheme
    let onDismiss: () -> Void

    private enum Step: Int {
        case topics = 1
        case notifications = 2
    }

    @State private var step: Step = .topics
    @State private var selectedTopicIds: Set<String> = []
    @State private var followAllTopics = false
    @State private var isProcessing = false

    private var sortedTopics: [Topic] {
        viewModel.topics.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var canContinueFromTopics: Bool {
        followAllTopics || !selectedTopicIds.isEmpty
    }

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
                Color(.sRGB, red: 0.98, green: 0.98, blue: 0.97, opacity: 1),
                Color(.sRGB, red: 0.94, green: 0.94, blue: 0.93, opacity: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            progressHeader
                .padding(.top, 20)
                .padding(.horizontal, 24)
                .staggeredReveal(index: 0)

            Group {
                switch step {
                case .topics:
                    topicsStep
                case .notifications:
                    notificationsStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundGradient.ignoresSafeArea())
        .interactiveDismissDisabled()
    }

    private var progressHeader: some View {
        HStack {
            Text("Apropos")
                .font(.system(.subheadline, weight: .semibold))
                .tracking(1.2)
                .textCase(.uppercase)
            Spacer()
            Text("\(step.rawValue) / 2")
                .font(.system(.caption, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var topicsStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Hvad vil du følge?")
                    .font(.system(.largeTitle, weight: .bold))
                Text("Vælg emner. Du kan ændre det senere på Min side.")
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 20)
            .staggeredReveal(index: 1, baseDelay: 0.04)

            ScrollView {
                FlowTopicChips(
                    topics: sortedTopics,
                    selectedIds: followAllTopics ? Set(sortedTopics.map(\.id)) : selectedTopicIds
                ) { topic in
                    followAllTopics = false
                    if selectedTopicIds.contains(topic.id) {
                        selectedTopicIds.remove(topic.id)
                    } else {
                        selectedTopicIds.insert(topic.id)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .staggeredReveal(index: 2, baseDelay: 0.06)

            VStack(spacing: 12) {
                Button {
                    step = .notifications
                } label: {
                    Text("Fortsæt")
                        .font(.system(.headline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canContinueFromTopics ? primaryButtonBackground : Color.primary.opacity(0.18))
                        .foregroundColor(canContinueFromTopics ? primaryButtonForeground : Color.primary.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canContinueFromTopics || isProcessing)

                Button {
                    followAllTopics = true
                    selectedTopicIds.removeAll()
                    step = .notifications
                } label: {
                    Text("Følg alt")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .staggeredReveal(index: 3, baseDelay: 0.08)
        }
    }

    private var notificationsStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text("Få besked om nyt")
                        .font(.system(.largeTitle, weight: .bold))
                        .multilineTextAlignment(.center)

                    Text(notificationsSubtitle)
                        .font(.system(.body, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.horizontal, 24)
            .staggeredReveal(index: 1, baseDelay: 0.04)

            Spacer()

            VStack(spacing: 14) {
                Button {
                    Task { await finish(allowNotifications: true) }
                } label: {
                    Text("Tillad notifikationer")
                        .font(.system(.headline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(primaryButtonBackground)
                        .foregroundColor(primaryButtonForeground)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)

                Button("Ikke nu") {
                    Task { await finish(allowNotifications: false) }
                }
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(.secondary)
                .disabled(isProcessing)

                Button("Tilbage") {
                    step = .topics
                }
                .font(.system(.footnote, weight: .medium))
                .foregroundStyle(.tertiary)
                .disabled(isProcessing)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .staggeredReveal(index: 2, baseDelay: 0.08)
        }
    }

    private var notificationsSubtitle: String {
        if followAllTopics || selectedTopicIds.isEmpty {
            return "Vi giver dig besked, når der er nyt på Apropos. Du kan altid ændre det under Min side."
        }
        let names = sortedTopics
            .filter { selectedTopicIds.contains($0.id) }
            .map(\.name)
        if names.count == 1 {
            return "Vi giver dig besked om nyt inden for \(names[0])."
        }
        if names.count <= 3 {
            let head = names.dropLast().joined(separator: ", ")
            return "Vi giver dig besked om nyt inden for \(head) og \(names.last!)."
        }
        return "Vi giver dig besked om nyt inden for dine \(names.count) valgte emner."
    }

    private var primaryButtonBackground: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

    private var primaryButtonForeground: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    @MainActor
    private func finish(allowNotifications: Bool) async {
        isProcessing = true
        let allCategoryIds = viewModel.topics.map(\.id)
        let selectedIds: [String] = followAllTopics ? [] : Array(selectedTopicIds)
        await notificationService.completeOnboarding(
            allowNotifications: allowNotifications,
            selectedCategoryIds: selectedIds,
            allCategoryIds: allCategoryIds
        )
        isProcessing = false
        onDismiss()
    }
}

// MARK: - Topic chip layout

private struct FlowTopicChips: View {
    let topics: [Topic]
    let selectedIds: Set<String>
    let onToggle: (Topic) -> Void

    var body: some View {
        FlexibleChipWrap(spacing: 10) {
            ForEach(topics) { topic in
                let isSelected = selectedIds.contains(topic.id)
                Button {
                    onToggle(topic)
                } label: {
                    Text(topic.name)
                        .font(.system(.body, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(isSelected ? Color.primary : Color.clear)
                        .foregroundStyle(isSelected ? Color(.systemBackground) : Color.primary)
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.primary.opacity(isSelected ? 0 : 0.22), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// Simple wrapping layout for topic chips without external dependencies.
private struct FlexibleChipWrap: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var height: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            height = max(height, y + rowHeight)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
