//
//  OnboardingNineView.swift
//  Native
//

import SwiftUI

struct OnboardingNineView: View {
    
    // MARK: - Properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) var dismiss
    
    /// Color scheme that is currently selected:
    @Environment(\.colorScheme) var colorScheme
    
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

private extension OnboardingNineView {
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

private extension OnboardingNineView {
    private var scroll: some View {
        scrollContent
            .ignoresSafeArea()
            .safeAreaPadding(
                .bottom,
                32
            )
    }
    
    private var scrollContent: some View {
        ScrollView {
            scrollItem
        }
    }
    
    private var scrollItem: some View {
        ImageBackgroundTitleSubtitleView(
            image: image,
            imageHeight: 424,
            imageBackgroundGradientStart: imageBackgroundGradientStart,
            imageBackgroundGradientEnd: imageBackgroundGradientEnd,
            imageCornerRadius: 0,
            title: "Latest Technologies",
            subtitle: "All of our resources are built with the latest first-party technologies that are offered by Apple.",
            titleSubtitleHorizontalPadding: 16
        )
    }
}

// MARK: - Toolbar:

private extension OnboardingNineView {
    private var toolbar: some View {
        BottomToolbarView(horizontalAlignment: .center) {
            getStartedLoginButtons
        }
    }
    
    private var getStartedLoginButtons: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            getStartedLoginButtonsContent
        }
    }
    
    @ViewBuilder
    private var getStartedLoginButtonsContent: some View {
        getStartedButton
        loginButton
    }
    
    private var getStartedButton: some View {
        ButtonView(
            title: "Get Started",
            action: getStarted
        )
    }
    
    private var loginButton: some View {
        ButtonView(
            title: "Login",
            titleColor: .primary,
            backgroundColor: .init(.secondarySystemBackground),
            isBackgroundColorGradient: false,
            action: login
        )
    }
}

// MARK: - Preview:

#Preview {
    OnboardingNineView()
}
