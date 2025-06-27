//
//  OnboardingOneView.swift
//  Native
//

import SwiftUI

struct OnboardingOneView: View {
    
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

private extension OnboardingOneView {
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

private extension OnboardingOneView {
    private var scroll: some View {
        scrollContent
            .safeAreaPadding(
                .all,
                16
            )
            .safeAreaPadding(
                .top,
                32
            )
            .safeAreaPadding(
                .bottom,
                16
            )
    }
    
    private var scrollContent: some View {
        ScrollView {
            scrollItem
        }
    }
    
    private var scrollItem: some View {
        VStack(
            alignment: .center,
            spacing: 48
        ) {
            scrollItemContent
        }
    }
    
    @ViewBuilder
    private var scrollItemContent: some View {
        title
        featuresContent
    }
}

// MARK: - Title:

private extension OnboardingOneView {
    private var title: some View {
        titleContent
            .font(.largeTitle.bold())
            .multilineTextAlignment(.center)
            .foregroundStyle(.primary)
    }
    
    private var titleContent: some View {
        Text("Supercharge Your \(Text("iOS App Project").foregroundStyle(titleGradient)) 🚀")
    }
}

// MARK: - Features:

private extension OnboardingOneView {
    private var featuresContent: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            featuresItem
        }
    }
    
    private var featuresItem: some View {
        ForEach(
            features,
            content: feature
        )
    }
    
    private func feature(_ feature: NT_Feature) -> some View {
        IconBackgroundTitleSubtitleView(
            icon: icon(feature),
            iconGradientStart: gradientStart(feature),
            iconGradientEnd: gradientEnd(feature),
            isIconColorGradient: true,
            isShowingIconBackground: false,
            iconSize: .fortyEightPixels,
            title: title(feature),
            subtitle: subtitle(feature),
            backgroundColor: .init(.secondarySystemBackground)
        )
    }
}

// MARK: - Toolbar:

private extension OnboardingOneView {
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
    OnboardingOneView()
}
