//
//  PasswordResetTwoView.swift
//  Native
//

import SwiftUI

struct PasswordResetTwoView: View {
    
    // MARK: - Properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) var dismiss
    
    /// Email address that is inputed by the user:
    @State var emailAddress: String = ""
    
    /// New password that is inputed by the user:
    @State var newPassword: String = ""
    
    /// Confirmed new password that is inputed by the user:
    @State var confirmedNewPassword: String = ""
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .localizedNavigationTitle(title: "Password Reset")
            .toolbarButton(
                title: "Cancel",
                font: .body,
                placement: .cancellationAction,
                action: dismiss.callAsFunction
            )
            .animation(
                .default,
                value: isUpdatePasswordDisabled
            )
            .navigationStack()
    }
}

// MARK: - Item:

private extension PasswordResetTwoView {
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

private extension PasswordResetTwoView {
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

private extension PasswordResetTwoView {
    @ViewBuilder
    private var textFields: some View {
        emailAddressTextField
        newPasswordContent
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
}

// MARK: - New password:

private extension PasswordResetTwoView {
    private var newPasswordContent: some View {
        newPasswordItem
            .headerProminence(.increased)
    }
    
    private var newPasswordItem: some View {
        Section("New Password") {
            newPasswordItemContent
        }
    }
    
    @ViewBuilder
    private var newPasswordItemContent: some View {
        newPasswordTextField
        confirmedNewPasswordTextField
    }
    
    private var newPasswordTextField: some View {
        TextFieldView(
            text: $newPassword,
            title: "New Password",
            isSecure: true,
            verticalPadding: 0,
            horizontalPadding: 0,
            isShowingBackground: false,
            cornerRadius: 0
        )
    }
    
    private var confirmedNewPasswordTextField: some View {
        TextFieldView(
            text: $confirmedNewPassword,
            title: "Confirm New Password",
            isSecure: true,
            verticalPadding: 0,
            horizontalPadding: 0,
            isShowingBackground: false,
            cornerRadius: 0
        )
    }
}

// MARK: - Toolbar:

private extension PasswordResetTwoView {
    private var toolbar: some View {
        BottomToolbarView(backgroundColor: .init(.systemGroupedBackground)) {
            updatePasswordButton
        }
    }
    
    private var updatePasswordButton: some View {
        ButtonView(
            title: "Update Password",
            isDisabled: isUpdatePasswordDisabled,
            action: updatePassword
        )
    }
}

// MARK: - Preview:

#Preview {
    PasswordResetTwoView()
}
