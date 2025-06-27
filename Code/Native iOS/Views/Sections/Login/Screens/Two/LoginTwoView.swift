//
//  LoginTwoView.swift
//  Native
//

import SwiftUI

struct LoginTwoView: View {
    
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

private extension LoginTwoView {
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
        form
        toolbar
    }
}

// MARK: - Form:

private extension LoginTwoView {
    private var form: some View {
        formContent
            .formStyle(.grouped)
    }
    
    private var formContent: some View {
        Form {
            textFields
        }
    }
}

// MARK: - Text fields:

private extension LoginTwoView {
    @ViewBuilder
    private var textFields: some View {
        emailAddressTextField
        passwordTextField
    }
    
    private var emailAddressTextField: some View {
        TextFieldView(
            text: $emailAddress,
            title: "Email Address",
            keyboardType: .emailAddress,
            verticalPadding: 0,
            horizontalPadding: 0,
            isShowingBackground: false,
            cornerRadius: 0
        )
    }
    
    private var passwordTextField: some View {
        TextFieldView(
            text: $password,
            title: "Password",
            isSecure: true,
            verticalPadding: 0,
            horizontalPadding: 0,
            isShowingBackground: false,
            cornerRadius: 0
        )
    }
}

// MARK: - Text fields:

private extension LoginTwoView {
    private var toolbar: some View {
        BottomToolbarView(backgroundColor: .init(.systemGroupedBackground)) {
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
            backgroundColor: .init(.secondarySystemGroupedBackground),
            isBackgroundColorGradient: false,
            action: resetPassword
        )
    }
}

// MARK: - Preview:

#Preview {
    LoginTwoView()
}
