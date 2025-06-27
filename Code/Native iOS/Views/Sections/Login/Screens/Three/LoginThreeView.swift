//
//  LoginThreeView.swift
//  Native
//

import SwiftUI

struct LoginThreeView: View {
    
    // MARK: - Properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) var dismiss
    
    /// Type of the account that is currently selected:
    @State var accountType: NT_AccountType = .personal
    
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
            .toolbarButton(
                title: "Cancel",
                font: .body,
                placement: .cancellationAction,
                action: dismiss.callAsFunction
            )
            .toolbarButton(
                title: "Sign Up",
                action: signUp
            )
            .onChange(
                of: accountType,
                accountTypeOnChange
            )
            .animation(
                .default,
                value: isLoginDisabled
            )
            .navigationStack()
    }
}

// MARK: - Item:

private extension LoginThreeView {
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

private extension LoginThreeView {
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
            alignment: .center,
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

private extension LoginThreeView {
    private var titleSubtitle: some View {
        TitleSubtitleView(
            title: "Welcome to AppLayouts 🚀",
            titleFont: .title2.bold(),
            titleAlignment: .center,
            subtitle: "You just need to log into your account below to start using the app.",
            subtitleFont: .body,
            subtitleAlignment: .center,
            alignment: .center,
            spacing: 12
        )
    }
}

// MARK: - Text fields:

private extension LoginThreeView {
    private var textFields: some View {
        VStack(
            alignment: .center,
            spacing: 16
        ) {
            textFieldsContent
        }
    }
    
    @ViewBuilder
    private var textFieldsContent: some View {
        accountTypePicker
        emailAddressTextField
        passwordTextField
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
            minHeight: 46
        )
    }
}

// MARK: - Account type picker:

private extension LoginThreeView {
    private var accountTypePicker: some View {
        accountTypePickerContent
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 248)
    }
    
    private var accountTypePickerContent: some View {
        Picker(
            "Account Type",
            selection: $accountType
        ) {
            accountTypesContent
        }
    }
    
    private var accountTypesContent: some View {
        ForEach(
            accountTypes,
            content: accountType
        )
    }
    
    private func accountType(_ type: NT_AccountType) -> some View {
        Text(title(type))
            .tag(type)
    }
}

// MARK: - Toolbar:

private extension LoginThreeView {
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
            backgroundColor: .init(.secondarySystemBackground),
            isBackgroundColorGradient: false,
            action: resetPassword
        )
    }
}

// MARK: - Preview:

#Preview {
    LoginThreeView()
}
