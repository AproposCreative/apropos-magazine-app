//
//  LoginFourView.swift
//  Native
//

import SwiftUI

struct LoginFourView: View {
    
    // MARK: - Properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) var dismiss
    
    /// Email address that is inputed by the user:
    @State var emailAddress: String = ""
    
    /// Password that is inputed by the user:
    @State var password: String = ""
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .background(imageContent)
            .toolbarButton(
                title: "Cancel",
                font: .body,
                color: toolbarButtonColor,
                placement: .cancellationAction,
                action: dismiss.callAsFunction
            )
            .toolbarButton(
                title: "Sign Up",
                color: toolbarButtonColor,
                action: signUp
            )
            .animation(
                .default,
                value: isLoginDisabled
            )
            .navigationStack()
            .darkColorScheme()
    }
}

// MARK: - Item:

private extension LoginFourView {
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

private extension LoginFourView {
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

private extension LoginFourView {
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
        titleSubtitle
        textFields
    }
}

// MARK: - Title and subtitle:

private extension LoginFourView {
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
        Text("You just need to log into your account below to start using the app.")
            .font(.title3)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Text fields:

private extension LoginFourView {
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
    }
    
    private var emailAddressTextField: some View {
        TextFieldView(
            text: $emailAddress,
            title: "Email Address",
            keyboardType: .emailAddress,
            backgroundColor: backgroundColor
        )
    }
    
    private var passwordTextField: some View {
        TextFieldView(
            text: $password,
            title: "Password",
            isSecure: true,
            minHeight: 46,
            backgroundColor: backgroundColor
        )
    }
}

// MARK: - Toolbar:

private extension LoginFourView {
    private var toolbar: some View {
        BottomToolbarView() {
            loginForgotPasswordButtons
        }
    }
    
    private var loginForgotPasswordButtons: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            loginForgotPasswordButtonsContent
        }
    }
    
    @ViewBuilder
    private var loginForgotPasswordButtonsContent: some View {
        loginButton
        forgotPasswordButton
    }
    
    private var loginButton: some View {
        ButtonView(
            title: "Login",
            isDisabled: isLoginDisabled,
            action: login
        )
    }
    
    private var forgotPasswordButton: some View {
        ButtonView(
            title: "Forgot Password?",
            titleColor: .primary,
            backgroundColor: backgroundColor,
            isBackgroundColorGradient: false,
            action: resetPassword
        )
    }
}

// MARK: - Preview:

#Preview {
    LoginFourView()
}
