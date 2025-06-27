//
//  LoginOneView.swift
//  Native
//

import SwiftUI

struct LoginOneView: View {
    
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
            .localizedNavigationTitle(title: "Login")
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
            .animation(
                .default,
                value: isLoginDisabled
            )
            .navigationStack()
    }
}

// MARK: - Item:

private extension LoginOneView {
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

private extension LoginOneView {
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
            textFields
        }
    }
}

// MARK: - Text fields:

private extension LoginOneView {
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

// MARK: - Toolbar:

private extension LoginOneView {
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
    LoginOneView()
}
