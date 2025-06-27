//
//  OnboardingSevenView.swift
//  Native
//

import SwiftUI

struct OnboardingSevenView: View {
    
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

private extension OnboardingSevenView {
    private var item: some View {
        VStack(
            alignment: .center,
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

private extension OnboardingSevenView {
    private var imageContent: some View {
        ZStack {
            imageItem
        }
    }
    
    @ViewBuilder
    private var imageItem: some View {
        imageItemContent
        imageOverlay
    }
    
    private var imageItemContent: some View {
        image
            .resizable()
            .ignoresSafeArea()
    }
    
    private var imageOverlay: some View {
        imageOverlayColor
            .ignoresSafeArea()
    }
}

// MARK: - Scroll:

private extension OnboardingSevenView {
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

private extension OnboardingSevenView {
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

private extension OnboardingSevenView {
    private var toolbar: some View {
        BottomToolbarView(horizontalAlignment: .center) {
            signUpLoginButtons
        }
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
            backgroundColor: .init(.systemFill),
            isBackgroundColorGradient: false,
            action: login
        )
    }
}

// MARK: - Preview:

#Preview {
    OnboardingSevenView()
}
