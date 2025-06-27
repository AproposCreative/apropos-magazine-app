//
//  EmptyStateThreeView.swift
//  Native
//

import SwiftUI

struct EmptyStateThreeView: View {
    
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

private extension EmptyStateThreeView {
    private var scroll: some View {
        scrollContent
            .safeAreaPadding(
                .top,
                48
            )
            .safeAreaPadding(
                .horizontal,
                16
            )
            .safeAreaPadding(
                .bottom,
                32
            )
    }
    
    private var scrollContent: some View {
        ScrollView {
            imageTitleSubtitleNewItemButton
        }
    }
}

// MARK: - Image, title, subtitle, and new item button:

private extension EmptyStateThreeView {
    private var imageTitleSubtitleNewItemButton: some View {
        VStack(
            alignment: .center,
            spacing: 24
        ) {
            imageTitleSubtitleNewItemButtonContent
        }
    }
    
    @ViewBuilder
    private var imageTitleSubtitleNewItemButtonContent: some View {
        imageTitleSubtitle
        newItemButton
    }
    
    private var imageTitleSubtitle: some View {
        ImageBackgroundTitleSubtitleView(
            image: image,
            imageAlignment: .top,
            title: "Nothing Here",
            subtitle: "We don’t have anything to display here."
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
    EmptyStateThreeView()
}
