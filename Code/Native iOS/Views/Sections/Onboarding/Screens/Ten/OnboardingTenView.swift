//
//  OnboardingTenView.swift
//  Native
//

import SwiftUI

struct OnboardingTenView: View {
    
    // MARK: - Properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) var dismiss
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .background(imageContent)
            .navigationStack()
            .darkColorScheme()
    }
}

// MARK: - Item:

private extension OnboardingTenView {
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

// MARK: - Image:

private extension OnboardingTenView {
    private var imageContent: some View {
        image
            .resizable()
            .ignoresSafeArea()
    }
}

// MARK: - Scroll:

private extension OnboardingTenView {
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
            iconTitleSubtitle
        }
    }
}

// MARK: - Icon, title and subtitle:

private extension OnboardingTenView {
    private var iconTitleSubtitle: some View {
        iconTitleSubtitleContent
            .accessibilityElement(children: .combine)
    }
    
    private var iconTitleSubtitleContent: some View {
        VStack(
            alignment: .center,
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
            alignment: .center,
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
            .multilineTextAlignment(.center)
            .foregroundStyle(.primary)
    }
    
    private var titleContent: some View {
        Text("Supercharge Your \(Text("iOS App Project").foregroundStyle(titleGradient)) 🚀")
    }
    
    private var subtitle: some View {
        subtitleContent
            .font(.title3)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
    }
    
    private var subtitleContent: some View {
        Text("Library of free and premium resources to help you launch your next app quicker.")
    }
}

// MARK: - Toolbar:

private extension OnboardingTenView {
    private var toolbar: some View {
        BottomToolbarView() {
            toolbarContent
        }
    }
    
    @ViewBuilder
    private var toolbarContent: some View {
        continueWithAppleSignUpLoginButtons
        notice
    }
    
    private var continueWithAppleSignUpLoginButtons: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            continueWithAppleSignUpLoginButtonsContent
        }
    }
    
    @ViewBuilder
    private var continueWithAppleSignUpLoginButtonsContent: some View {
        continueWithAppleButton
        signUpButton
        loginButton
    }
    
    private var continueWithAppleButton: some View {
        SignInWithAppleButtonView(
            style: .white,
            onRequest: onRequestContinueWithApple,
            onCompletion: onCompletionContinueWithApple
        )
    }
    
    private var signUpButton: some View {
        ButtonView(
            title: "Sign Up",
            action: signUp
        )
    }
    
    private var loginButton: some View {
        ButtonView(
            title: "Login",
            titleColor: .primary,
            backgroundColor: .init(.systemFill),
            isBackgroundColorGradient: false,
            action: login
        )
    }
    
    private var notice: some View {
        noticeContent
            .buttonStyle(.plain)
    }
    
    private var noticeContent: some View {
        Link(destination: termsOfServiceLink) {
            noticeLabel
        }
    }
    
    private var noticeLabel: some View {
        noticeLabelContent
            .font(.footnote)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.secondary)
    }
    
    private var noticeLabelContent: some View {
        Text("By signing up, you acknowledge that you have read and agree to the \(Text("terms of service").underline().foregroundStyle(.primary)).")
    }
}

// MARK: - Preview:

#Preview {
    OnboardingTenView()
}
