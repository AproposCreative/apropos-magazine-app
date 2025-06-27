//
//  PaywallFourteenTimelineView.swift
//  Native
//

import SwiftUI

struct PaywallFourteenTimelineView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// Color scheme that is currently selected:
    @Environment(\.colorScheme) var colorScheme
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .padding(
                .horizontal,
                16
            )
    }
}

// MARK: - Item:

private extension PaywallFourteenTimelineView {
    private var item: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        SectionHeaderView(title: "What Happens Next")
        timelineItemsContent
    }
}

// MARK: - Timeline items:

private extension PaywallFourteenTimelineView {
    private var timelineItemsContent: some View {
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
        HStack(
            alignment: .top,
            spacing: 12
        ) {
            timelineItemContent(item)
        }
    }
    
    @ViewBuilder
    private func timelineItemContent(_ item: NT_Timeline) -> some View {
        timelineItemIcon(item)
        timelineItemTitleSubtitle(item)
    }
    
    private func timelineItemIcon(_ item: NT_Timeline) -> some View {
        timelineItemIconContent(item)
            .padding(4)
            .frame(
                maxHeight: .infinity,
                alignment: .top
            )
            .background(iconBackgroundColor)
            .unevenRoundedCorners(
                topLeadingCornerRadius: iconBackgroundTopCornerRadius(item),
                bottomLeadingCornerRadius: iconBackgroundBottomCornerRadius(item),
                bottomTrailingCornerRadius: iconBackgroundBottomCornerRadius(item),
                topTrailingCornerRadius: iconBackgroundTopCornerRadius(item)
            )
    }
    
    private func timelineItemIconContent(_ item: NT_Timeline) -> some View {
        IconBackgroundView(
            icon: icon(item),
            isCircularBackground: true,
            size: .thirtyTwoPixels
        )
    }
    
    private func timelineItemTitleSubtitle(_ item: NT_Timeline) -> some View {
        timelineItemTitleSubtitleContent(item)
            .padding(
                .top,
                timelineItemTopPadding
            )
            .padding(
                .bottom,
                timelineItemBottomPadding
            )
    }
    
    private func timelineItemTitleSubtitleContent(_ item: NT_Timeline) -> some View {
        TitleSubtitleView(
            title: title(item),
            subtitle: subtitle(item)
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        PaywallFourteenTimelineView()
    }
    .safeAreaPadding(
        .top,
        16
    )
    .safeAreaPadding(
        .bottom,
        32
    )
}
