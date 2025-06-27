//
//  SignUpFiveView.swift
//  Native
//

import SwiftUI

struct SignUpFiveView: View {
    
    // MARK: - Properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) var dismiss
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// Email address that is inputed by the user:
    @State var emailAddress: String = ""
    
    /// Password that is inputed by the user:
    @State var password: String = ""
    
    /// Confirmed password that is inputed by the user:
    @State var confirmedPassword: String = ""
    
    /// 'Bool' value indicating whether or not the user has agreed to the terms of service and the privacy policy:
    @State var isAgreedToTermsOfServiceAndPrivacyPolicy: Bool = false
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .toolbarButton(
                title: "Cancel",
                font: .body,
                placement: .cancellationAction,
                action: dismiss.callAsFunction
            )
            .toolbarButton(
                title: "Login",
                action: login
            )
            .animation(
                .default,
                value: isCreateAccountDisabled
            )
            .animation(
                .default,
                value: isAgreedToTermsOfServiceAndPrivacyPolicy
            )
            .navigationStack()
    }
}

// MARK: - Item:

private extension SignUpFiveView {
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

private extension SignUpFiveView {
    private var scroll: some View {
        scrollContent
            .safeAreaPadding(
                .top,
                16
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
        iconTitleSubtitle
        DividerView()
        textFields
    }
}

// MARK: - Icon, title and subtitle:

private extension SignUpFiveView {
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
        Text("Welcome to \(Text("AppLayouts").foregroundStyle(titleGradient)) 🚀")
            .font(.largeTitle.bold())
            .multilineTextAlignment(.leading)
            .foregroundStyle(.primary)
    }
    
    private var subtitle: some View {
        Text("You just need to create a free account below to start using the app.")
            .font(.title3)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Text fields:

private extension SignUpFiveView {
    private var textFields: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            textFieldsContent
        }
    }
    
    @ViewBuilder
    private var textFieldsContent: some View {
        emailAddressTextField
        passwordTextField
        confirmedPasswordTextField
        notice
    }
    
    private var emailAddressTextField: some View {
        TextFieldView(
            text: $emailAddress,
            title: "Email Address",
            keyboardType: .emailAddress
        )
    }
    
    private var passwordTextField: some View {
        TextFieldView(
            text: $password,
            title: "Password",
            isSecure: true,
            minHeight: passwordTextFieldMinHeight
        )
    }
    
    private var confirmedPasswordTextField: some View {
        TextFieldView(
            text: $confirmedPassword,
            title: "Confirm Password",
            isSecure: true,
            minHeight: passwordTextFieldMinHeight
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
            alignment: .top,
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
        agreeToTermsOfServiceAndPrivacyPolicyButton
        noticeTitle
    }
    
    private var agreeToTermsOfServiceAndPrivacyPolicyButton: some View {
        agreeToTermsOfServiceAndPrivacyPolicyButtonContent
            .accessibilityLabel("I acknowledge that I have read and agree to the terms of service and privacy policy.")
    }
    
    private var agreeToTermsOfServiceAndPrivacyPolicyButtonContent: some View {
        SelectButtonView(
            selectedFont: .headline,
            unselectedFont: .body,
            unselectedColor: .init(.systemFill),
            isUnselectedGradient: false,
            frame: 24,
            isSelected: isAgreedToTermsOfServiceAndPrivacyPolicy,
            action: agreeToTermsOfServiceAndPrivacyPolicy
        )
    }
    
    private var noticeTitle: some View {
        noticeTitleContent
            .font(.footnote)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.secondary)
    }
    
    private var noticeTitleContent: some View {
        Text("I acknowledge that I have read and agree to the \(Text("[terms of service](https://www.applayouts.com/terms-of-use)").underline().foregroundStyle(.accent)) and \(Text("[privacy policy](https://www.applayouts.com/privacy-policy)").underline().foregroundStyle(.accent)).")
    }
}

// MARK: - Toolbar:

private extension SignUpFiveView {
    private var toolbar: some View {
        BottomToolbarView() {
            createAccountButton
        }
    }
    
    private var createAccountButton: some View {
        ButtonView(
            title: "Create Account",
            isDisabled: isCreateAccountDisabled,
            action: createAccount
        )
    }
}

// MARK: - Preview:

#Preview {
    SignUpFiveView()
}
