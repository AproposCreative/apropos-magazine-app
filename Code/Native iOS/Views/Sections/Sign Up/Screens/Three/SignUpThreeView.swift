//
//  SignUpThreeView.swift
//  Native
//

import SwiftUI

struct SignUpThreeView: View {
    
    // MARK: - Properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) var dismiss
    
    /// Email address that is inputed by the user:
    @State var emailAddress: String = ""
    
    /// Username that is inputed by the user:
    @State var username: String = ""
    
    /// Password that is inputed by the user:
    @State var password: String = ""
    
    /// Confirmed password that is inputed by the user:
    @State var confirmedPassword: String = ""
    
    /// First name that is inputed by the user:
    @State var firstName: String = ""
    
    /// Last name that is inputed by the user:
    @State var lastName: String = ""
    
    /// Street name that is inputed by the user:
    @State var streetName: String = ""
    
    /// City that is inputed by the user:
    @State var city: String = ""
    
    /// ZIP code that is inputed by the user:
    @State var zipCode: String = ""
    
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
            .toolbarButton(
                title: "Login",
                action: login
            )
            .animation(
                .default,
                value: isCreateAccountDisabled
            )
            .navigationStack()
    }
}

// MARK: - Item:

private extension SignUpThreeView {
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

private extension SignUpThreeView {
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

private extension SignUpThreeView {
    private var textFields: some View {
        VStack(
            alignment: .leading,
            spacing: 32
        ) {
            textFieldsContent
        }
    }
    
    @ViewBuilder
    private var textFieldsContent: some View {
        accountDetails
        personalDetails
        address
    }
}

// MARK: - Account details:

private extension SignUpThreeView {
    private var accountDetails: some View {
        ExpandableContentView(
            isExpanded: true,
            title: "Account Details"
        ) {
            accountDetailsContent
        }
    }
    
    @ViewBuilder
    private var accountDetailsContent: some View {
        emailAddressTextField
        usernameTextField
        passwordTextField
        confirmedPasswordTextField
    }
    
    private var emailAddressTextField: some View {
        TextFieldView(
            text: $emailAddress,
            title: "Email Address",
            keyboardType: .emailAddress
        )
    }
    
    private var usernameTextField: some View {
        TextFieldView(
            text: $username,
            title: "Username"
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
}

// MARK: - Personal details:

private extension SignUpThreeView {
    private var personalDetails: some View {
        ExpandableContentView(title: "Personal Details") {
            personalDetailsContent
        }
    }
    
    @ViewBuilder
    private var personalDetailsContent: some View {
        firstNameTextField
        lastNameTextField
    }
    
    private var firstNameTextField: some View {
        TextFieldView(
            text: $firstName,
            title: "First Name"
        )
    }
    
    private var lastNameTextField: some View {
        TextFieldView(
            text: $firstName,
            title: "Last Name"
        )
    }
}

// MARK: - Address:

private extension SignUpThreeView {
    private var address: some View {
        ExpandableContentView(title: "Address") {
            addressContent
        }
    }
    
    @ViewBuilder
    private var addressContent: some View {
        streetNameTextField
        cityTextField
        zipCodeTextField
    }
    
    private var streetNameTextField: some View {
        TextFieldView(
            text: $streetName,
            title: "Street Name"
        )
    }
    
    private var cityTextField: some View {
        TextFieldView(
            text: $city,
            title: "City"
        )
    }
    
    private var zipCodeTextField: some View {
        TextFieldView(
            text: $zipCode,
            title: "ZIP Code"
        )
    }
}

// MARK: - Toolbar:

private extension SignUpThreeView {
    private var toolbar: some View {
        BottomToolbarView() {
            toolbarContent
        }
    }
    
    @ViewBuilder
    private var toolbarContent: some View {
        notice
        createAccountButton
    }
    
    private var createAccountButton: some View {
        ButtonView(
            title: "Create Account",
            isDisabled: isCreateAccountDisabled,
            action: createAccount
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
    SignUpThreeView()
}
