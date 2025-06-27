//
//  OnboardingElevenView.swift
//  Native
//

import SwiftUI

struct OnboardingElevenView: View {
    
    // MARK: - Properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) var dismiss
    
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

private extension OnboardingElevenView {
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

private extension OnboardingElevenView {
    private var scroll: some View {
        ScrollView {
            featuresScroll
        }
    }
}

// MARK: - Features scroll:

private extension OnboardingElevenView {
    private var featuresScroll: some View {
        featuresScrollContent
            .scrollIndicators(.hidden)
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

private extension OnboardingElevenView {
    private var featuresContent: some View {
        HStack(
            alignment: .top,
            spacing: 32
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
            .scrollTransition(axis: .horizontal) { content, phase in
                content
                    .scaleEffect(scaleEffect(inPhase: phase))
            }
            .id(feature)
    }
    
    private func featureContent(_ feature: NT_Feature) -> some View {
        IconBackgroundBadgeTitleSubtitleView(
            icon: icon(feature),
            iconBackgroundColor: color(feature),
            iconBackgroundGradientStart: gradientStart(feature),
            iconBackgroundGradientEnd: gradientEnd(feature),
            badgeTitle: badgeTitle(feature),
            badgeBackgroundColor: color(feature),
            badgeBackgroundGradientStart: gradientStart(feature),
            badgeBackgroundGradientEnd: gradientEnd(feature),
            title: title(feature),
            subtitle: subtitle(feature)
        )
    }
}

// MARK: - Toolbar:

private extension OnboardingElevenView {
    private var toolbar: some View {
        BottomToolbarView(horizontalAlignment: .center) {
            toolbarContent
        }
    }
    
    @ViewBuilder
    private var toolbarContent: some View {
        pagination
        signUpLoginButtons
    }
    
    private var pagination: some View {
        PaginationView(
            current: $currentFeature,
            all: features
        )
    }
    
    private var signUpLoginButtons: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            signUpLoginButtonsContent
        }
    }
    
    @ViewBuilder
    private var signUpLoginButtonsContent: some View {
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
}

// MARK: - Preview:

#Preview {
    OnboardingElevenView()
}
