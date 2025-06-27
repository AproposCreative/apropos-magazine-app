//
//  OnboardingFourView.swift
//  Native
//

import SwiftUI

struct OnboardingFourView: View {
    
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

private extension OnboardingFourView {
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

private extension OnboardingFourView {
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
            imageTitleSubtitle
        }
    }
}

// MARK: - Image, title and subtitle:

private extension OnboardingFourView {
    private var imageTitleSubtitle: some View {
        ImageBackgroundTitleSubtitleView(
            image: image,
            imageHeight: 344,
            imageAlignment: .top,
            imageBackgroundColor: backgroundColor,
            isImageBackgroundColorGradient: false,
            title: "Latest Technologies",
            subtitle: "All of our resources are built with the latest first-party technologies that are offered by Apple."
        )
    }
}

// MARK: - Toolbar:

private extension OnboardingFourView {
    private var toolbar: some View {
        BottomToolbarView(
            spacing: 8,
            contentAlignment: .horizontal
        ) {
            signUpLoginButtonsContent
        }
    }
    
    @ViewBuilder
    private var signUpLoginButtonsContent: some View {
        loginButton
        signUpButton
    }
    
    private var loginButton: some View {
        ButtonView(
            title: "Login",
            titleColor: .primary,
            backgroundColor: backgroundColor,
            isBackgroundColorGradient: false,
            action: login
        )
    }
    
    private var signUpButton: some View {
        ButtonView(
            title: "Sign Up",
            action: signUp
        )
    }
}

// MARK: - Preview:

#Preview {
    OnboardingFourView()
}
