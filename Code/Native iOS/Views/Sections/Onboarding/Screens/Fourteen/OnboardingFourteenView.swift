//
//  OnboardingFourteenView.swift
//  Native
//

import SwiftUI

struct OnboardingFourteenView: View {
    
    // MARK: - Properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) var dismiss
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    // MARK: - Private properties:
    
    /// 'Bool' value indicating whether or not the user has agreed to the terms of service:
    @State private var isAgreedToTermsOfService: Bool = false
    
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

private extension OnboardingFourteenView {
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

private extension OnboardingFourteenView {
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
            scrollItem
        }
    }
    
    private var scrollItem: some View {
        VStack(
            alignment: .leading,
            spacing: 32
        ) {
            scrollItemContent
        }
    }
    
    @ViewBuilder
    private var scrollItemContent: some View {
        imageTitleSubtitle
        DividerView()
        featuresContent
    }
}

// MARK: - Image, title and subtitle:

private extension OnboardingFourteenView {
    private var imageTitleSubtitle: some View {
        imageTitleSubtitleContent
            .accessibilityElement(children: .combine)
    }
    
    private var imageTitleSubtitleContent: some View {
        VStack(
            alignment: .leading,
            spacing: 48
        ) {
            imageTitleSubtitleItem
        }
    }
    
    @ViewBuilder
    private var imageTitleSubtitleItem: some View {
        imageContent
        titleSubtitle
    }
    
    private var imageContent: some View {
        ImageBackgroundView(
            image: image,
            alignment: .top
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

// MARK: - Features:

private extension OnboardingFourteenView {
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
            icon: Icons.checkmarkCircle,
            isIconColorGradient: true,
            isShowingIconBackground: false,
            iconSize: .thirtyTwoPixels,
            title: subtitle(feature),
            isShowingSubtitle: false,
            subtitle: "",
            verticalPadding: 0,
            horizontalPadding: 0,
            isShowingBackground: false,
            cornerRadius: 0
        )
    }
}

// MARK: - Toolbar:

private extension OnboardingFourteenView {
    private var toolbar: some View {
        BottomToolbarView() {
            toolbarContent
        }
    }
    
    @ViewBuilder
    private var toolbarContent: some View {
        signUpButton
        notice
    }
    
    private var signUpButton: some View {
        ButtonView(
            title: "Sign Up",
            action: signUp
        )
    }
    
    @ViewBuilder
    private var notice: some View {
        if shouldMoveContent {
            verticalNoticeContent
        } else {
            horizontalNoticeContent
        }
    }
    
    private var horizontalNoticeContent: some View {
        HStack(
            alignment: .center,
            spacing: noticeSpacing
        ) {
            noticeItem
        }
    }
    
    private var verticalNoticeContent: some View {
        VStack(
            alignment: .leading,
            spacing: noticeSpacing
        ) {
            noticeItem
        }
    }
    
    @ViewBuilder
    private var noticeItem: some View {
        agreeToTermsOfServiceToggle
        noticeLink
    }
    
    private var agreeToTermsOfServiceToggle: some View {
        agreeToTermsOfServiceToggleContent
            .labelsHidden()
    }
    
    private var agreeToTermsOfServiceToggleContent: some View {
        Toggle(
            "I acknowledge that I have read and agree to the terms of service.",
            isOn: $isAgreedToTermsOfService
        )
    }
    
    private var noticeLink: some View {
        noticeLinkContent
            .buttonStyle(.plain)
    }
    
    private var noticeLinkContent: some View {
        Link(destination: termsOfServiceLink) {
            noticeLinkLabel
        }
    }
    
    private var noticeLinkLabel: some View {
        noticeLinkLabelContent
            .font(.footnote)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.secondary)
    }
    
    private var noticeLinkLabelContent: some View {
        Text("I acknowledge that I have read and agree to the \(Text("terms of service").underline().foregroundStyle(.accent)).")
    }
}

// MARK: - Preview:

#Preview {
    OnboardingFourteenView()
}
