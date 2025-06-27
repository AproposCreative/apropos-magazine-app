//
//  OnboardingThreeView.swift
//  Native
//

import SwiftUI

struct OnboardingThreeView: View {
    
    // MARK: - Properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) var dismiss
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .navigationStack()
    }
}

// MARK: - Item:

private extension OnboardingThreeView {
    private var item: some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        scroll
        toolbar
    }
}

// MARK: - Scroll:

private extension OnboardingThreeView {
    private var scroll: some View {
        scrollContent
            .safeAreaPadding(
                .vertical,
                32
            )
            .safeAreaPadding(
                .horizontal,
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

private extension OnboardingThreeView {
    private var iconTitleSubtitle: some View {
        iconTitleSubtitleContent
            .accessibilityElement(children: .combine)
    }
    
    private var iconTitleSubtitleContent: some View {
        VStack(
            alignment: .leading,
            spacing: 32
        ) {
            iconTitleSubtitleItem
        }
    }
    
    @ViewBuilder
    private var iconTitleSubtitleItem: some View {
        icon
        titleSubtitle
    }
    
    private var icon: some View {
        IconBackgroundView(
            icon: Icons.chevronLeftForwardslashChevronRight,
            size: .ninetySixPixels
        )
    }
    
    private var titleSubtitle: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            titleSubtitleContent
        }
    }
    
    @ViewBuilder
    private var titleSubtitleContent: some View {
        title
        subtitle
    }
    
    private var title: some View {
        titleContent
            .font(.largeTitle.bold())
            .multilineTextAlignment(.leading)
            .foregroundStyle(.primary)
    }
    
    private var titleContent: some View {
        Text("Supercharge Your \(Text("iOS App Project").foregroundStyle(titleGradient)) 🚀")
    }
    
    private var subtitle: some View {
        subtitleContent
            .font(.title3)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.secondary)
    }
    
    private var subtitleContent: some View {
        Text("Library of free and premium resources to help you launch your next app quicker.")
    }
}

// MARK: - Toolbar:

private extension OnboardingThreeView {
    private var toolbar: some View {
        BottomToolbarView() {
            getStartedButton
        }
    }
    
    private var getStartedButton: some View {
        ButtonView(
            title: "Get Started",
            action: getStarted
        )
    }
}

// MARK: - Preview:

#Preview {
    OnboardingThreeView()
}
