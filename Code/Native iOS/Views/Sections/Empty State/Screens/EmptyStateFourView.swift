//
//  EmptyStateFourView.swift
//  Native
//

import SwiftUI

struct EmptyStateFourView: View {
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        scroll
            .navigationStack()
    }
}

// MARK: - Scroll:

private extension EmptyStateFourView {
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
        iconTitleSubtitle
    }
    
    private var scrollItemSpacer: some View {
        Spacer()
            .containerRelativeFrame(
                .vertical,
                alignment: .center
            )
    }
}

// MARK: - Icon, title and subtitle:

private extension EmptyStateFourView {
    private var iconTitleSubtitle: some View {
        IconBackgroundTitleSubtitleView(
            icon: Icons.tray,
            iconColor: .secondary,
            isShowingIconBackground: false,
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
}

// MARK: - Preview:

#Preview {
    EmptyStateFourView()
}
