//
//  EmptyStateFiveView.swift
//  Native
//

import SwiftUI

struct EmptyStateFiveView: View {
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        scroll
            .background(Color(.systemGroupedBackground))
            .navigationStack()
    }
}

// MARK: - Scroll:

private extension EmptyStateFiveView {
    private var scroll: some View {
        scrollContent
            .safeAreaPadding(
                .all,
                16
            )
    }
    
    private var scrollContent: some View {
        ScrollView {
            scrollItem
        }
    }
    
    private var scrollItem: some View {
        ZStack {
            scrollItemContent
        }
    }
    
    @ViewBuilder
    private var scrollItemContent: some View {
        scrollItemSpacer
        iconTitleSubtitleNewItemButton
    }
    
    private var scrollItemSpacer: some View {
        Spacer()
            .containerRelativeFrame(
                .vertical,
                alignment: .center
            )
    }
}

// MARK: - Icon, title, subtitle, and new item button:

private extension EmptyStateFiveView {
    private var iconTitleSubtitleNewItemButton: some View {
        VStack(
            alignment: .center,
            spacing: 24
        ) {
            iconTitleSubtitleNewItemButtonContent
        }
    }
    
    @ViewBuilder
    private var iconTitleSubtitleNewItemButtonContent: some View {
        iconTitleSubtitle
        newItemButton
    }
    
    private var iconTitleSubtitle: some View {
        IconBackgroundTitleSubtitleView(
            icon: Icons.tray,
            iconSize: .sixtyFourPixels,
            title: "Nothing Here",
            titleFont: .title2.bold(),
            titleAlignment: .center,
            subtitle: "We don’t have anything to display here.",
            subtitleFont: .body,
            subtitleAlignment: .center,
            titleSubtitleAlignment: .center,
            titleSubtitleSpacing: 12,
            titleSubtitleMaxWidthAlignment: .center,
            alignment: .vertical,
            horizontalAlignment: .center,
            spacing: 24,
            verticalPadding: 0,
            horizontalPadding: 0,
            isShowingBackground: false,
            cornerRadius: 0
        )
    }
    
    private var newItemButton: some View {
        ButtonView(
            title: "New Item",
            icon: Icons.plusCircle,
            style: .titleAndIcon,
            action: newItem
        )
    }
}

// MARK: - Preview:

#Preview {
    EmptyStateFiveView()
}
