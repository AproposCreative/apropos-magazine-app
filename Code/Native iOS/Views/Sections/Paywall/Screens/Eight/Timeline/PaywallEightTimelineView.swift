//
//  PaywallEightTimelineView.swift
//  Native
//

import SwiftUI

struct PaywallEightTimelineView: View {
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            item
        }
    }
}

// MARK: - Item:

private extension PaywallEightTimelineView {
    @ViewBuilder
    private var item: some View {
        SectionHeaderView(title: "What Happens Next")
        timelineItemsContent
    }
}

// MARK: - Timeline items:

private extension PaywallEightTimelineView {
    private var timelineItemsContent: some View {
        timelineItemsItem
            .contentBackground(
                verticalPadding: 0,
                horizontalPadding: 0
            )
    }
    
    private var timelineItemsItem: some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            timelineItemsItemContent
        }
    }
    
    private var timelineItemsItemContent: some View {
        ForEach(
            timelineItems,
            content: timelineItem
        )
    }
    
    private func timelineItem(_ item: NT_Timeline) -> some View {
        IconBackgroundTitleSubtitleView(
            icon: icon(item),
            isIconColorGradient: true,
            isShowingIconBackground: false,
            title: title(item),
            subtitle: subtitle(item),
            cornerRadius: 0
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        PaywallEightTimelineView()
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .background(Color(.systemGroupedBackground))
}
