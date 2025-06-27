//
//  EmptyStateTwoView.swift
//  Native
//

import SwiftUI

struct EmptyStateTwoView: View {
    
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

private extension EmptyStateTwoView {
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
        titleSubtitleNewItemButton
    }
    
    private var scrollItemSpacer: some View {
        Spacer()
            .containerRelativeFrame(
                .vertical,
                alignment: .center
            )
    }
}

// MARK: - Title, subtitle, and new item button:

private extension EmptyStateTwoView {
    private var titleSubtitleNewItemButton: some View {
        VStack(
            alignment: .center,
            spacing: 24
        ) {
            titleSubtitleNewItemButtonContent
        }
    }
    
    @ViewBuilder
    private var titleSubtitleNewItemButtonContent: some View {
        titleSubtitle
        newItemButton
    }
    
    private var titleSubtitle: some View {
        TitleSubtitleView(
            title: "Nothing Here",
            titleFont: .title2.bold(),
            titleAlignment: .center,
            subtitle: "We don’t have anything to display here.",
            subtitleFont: .body,
            subtitleAlignment: .center,
            alignment: .center,
            spacing: 12,
            maxWidthAlignment: .center
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
    EmptyStateTwoView()
}
