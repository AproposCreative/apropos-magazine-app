//
//  SignUpTwoView.swift
//  Native
//

import SwiftUI

struct SignUpTwoView: View {
    
    // MARK: - Properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) var dismiss
    
    /// Email address that is inputed by the user:
    @State var emailAddress: String = ""
    
    /// Password that is inputed by the user:
    @State var password: String = ""
    
    /// Confirmed password that is inputed by the user:
    @State var confirmedPassword: String = ""
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .localizedNavigationTitle(title: "Sign Up")
            .toolbarButton(
                title: "Cancel",
                font: .body,
                placement: .cancellationAction,
                action: dismiss.callAsFunction
            )
            .animation(
                .default,
                value: isCreateAccountDisabled
            )
            .navigationStack()
    }
}

// MARK: - Item:

private extension SignUpTwoView {
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

private extension SignUpTwoView {
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

private extension SignUpTwoView {
    @ViewBuilder
    private var textFields: some View {
        emailAddressTextField
        passwordTextField
        confirmedPasswordTextField
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
    
    private var confirmedPasswordTextField: some View {
        TextFieldView(
            text: $confirmedPassword,
            title: "Confirm Password",
            isSecure: true,
            verticalPadding: 0,
            horizontalPadding: 0,
            isShowingBackground: false,
            cornerRadius: 0
        )
    }
}

// MARK: - Toolbar:

private extension SignUpTwoView {
    private var toolbar: some View {
        BottomToolbarView(backgroundColor: .init(.systemGroupedBackground)) {
            toolbarContent
        }
    }
    
    @ViewBuilder
    private var toolbarContent: some View {
        notice
        createAccountLoginButtons
    }
    
    private var createAccountLoginButtons: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            createAccountLoginButtonsContent
        }
    }
    
    @ViewBuilder
    private var createAccountLoginButtonsContent: some View {
        createAccountButton
        loginButton
    }
    
    private var createAccountButton: some View {
        ButtonView(
            title: "Create Account",
            isDisabled: isCreateAccountDisabled,
            action: createAccount
        )
    }
    
    private var loginButton: some View {
        ButtonView(
            title: "Login",
            titleColor: .primary,
            backgroundColor: .init(.secondarySystemGroupedBackground),
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
    SignUpTwoView()
}
