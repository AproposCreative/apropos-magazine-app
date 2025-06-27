//
//  OnboardingFifteenView.swift
//  Native
//

import SwiftUI

struct OnboardingFifteenView: View {
    
    // MARK: - Properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) var dismiss
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// Color scheme that is currently selected:
    @Environment(\.colorScheme) var colorScheme
    
    // MARK: - Private properties:
    
    /// Feature that is currently shown:
    @State private var currentFeature: NT_Feature? = .latestTechnologies
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .animation(
                .default,
                value: currentFeature
            )
            .navigationStack()
    }
}

// MARK: - Item:

private extension OnboardingFifteenView {
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

private extension OnboardingFifteenView {
    private var scroll: some View {
        ScrollView {
            featuresScroll
        }
    }
}

// MARK: - Features scroll:

private extension OnboardingFifteenView {
    private var featuresScroll: some View {
        featuresScrollContent
            .ignoresSafeArea()
            .scrollIndicators(.hidden)
            .safeAreaPadding(
                .bottom,
                32
            )
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $currentFeature)
    }
    
    private var featuresScrollContent: some View {
        ScrollView(.horizontal) {
            featuresScrollItem
        }
    }
    
    private var featuresScrollItem: some View {
        featuresContent
            .scrollTargetLayout()
    }
}

// MARK: - Features:

private extension OnboardingFifteenView {
    private var featuresContent: some View {
        HStack(
            alignment: .top,
            spacing: 0
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
        featureContent(feature)
            .containerRelativeFrame(.horizontal)
            .id(feature)
    }
    
    private func featureContent(_ feature: NT_Feature) -> some View {
        ImageBackgroundTitleSubtitleView(
            image: image(feature),
            imageHeight: 344,
            imageAlignment: imageAlignment(feature),
            imageCornerRadius: 0,
            title: title(feature),
            subtitle: subtitle(feature),
            titleSubtitleHorizontalPadding: 16
        )
    }
}

// MARK: - Toolbar:

private extension OnboardingFifteenView {
    private var toolbar: some View {
        BottomToolbarView(horizontalAlignment: .center) {
            toolbarContent
        }
    }
    
    @ViewBuilder
    private var toolbarContent: some View {
        pagination
        continueWithAppleSignUpLoginButtons
        notice
    }
    
    private var pagination: some View {
        PaginationView(
            current: $currentFeature,
            all: features
        )
    }
    
    private var continueWithAppleSignUpLoginButtons: some View {
        VStack(
            alignment: .leading,
            spacing: buttonsSpacing
        ) {
            continueWithAppleSignUpLoginButtonsContent
        }
    }
    
    @ViewBuilder
    private var continueWithAppleSignUpLoginButtonsContent: some View {
        continueWithAppleButton
        signUpLoginButtons
    }
    
    @ViewBuilder
    private var continueWithAppleButton: some View {
        if isDarkColorScheme {
            darkContinueWithAppleButton
        } else {
            lightContinueWithAppleButton
        }
    }
    
    private var darkContinueWithAppleButton: some View {
        SignInWithAppleButtonView(
            style: .white,
            onRequest: onRequestContinueWithApple,
            onCompletion: onCompletionContinueWithApple
        )
    }
    
    private var lightContinueWithAppleButton: some View {
        SignInWithAppleButtonView(
            style: .black,
            onRequest: onRequestContinueWithApple,
            onCompletion: onCompletionContinueWithApple
        )
    }
    
    @ViewBuilder
    private var signUpLoginButtons: some View {
        if shouldMoveContent {
            verticalSignUpLoginButtonsContent
        } else {
            horizontalSignUpLoginButtonsContent
        }
    }
    
    private var horizontalSignUpLoginButtonsContent: some View {
        HStack(
            alignment: .top,
            spacing: buttonsSpacing
        ) {
            signUpLoginButtonsItem
        }
    }
    
    private var verticalSignUpLoginButtonsContent: some View {
        VStack(
            alignment: .leading,
            spacing: buttonsSpacing
        ) {
            signUpLoginButtonsItem
        }
    }
    
    @ViewBuilder
    private var signUpLoginButtonsItem: some View {
        signUpButton
        loginButton
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
            backgroundColor: .init(.secondarySystemBackground),
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
        Text("By signing up, you acknowledge that you have read and agree to the \(Text("terms of service").underline().foregroundStyle(.accent)).")
    }
}

// MARK: - Preview:

#Preview {
    OnboardingFifteenView()
}
