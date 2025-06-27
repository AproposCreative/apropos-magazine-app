//
//  PasswordResetFourView.swift
//  Native
//

import SwiftUI

struct PasswordResetFourView: View {
    
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

private extension PasswordResetFourView {
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

private extension PasswordResetFourView {
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

private extension PasswordResetFourView {
    private var titleSubtitle: some View {
        TitleSubtitleView(
            title: "Password Reset",
            titleFont: .title2.bold(),
            titleAlignment: .center,
            subtitle: "Please enter and confirm your email address below in order to reset your password.",
            subtitleFont: .body,
            subtitleAlignment: .center,
            alignment: .center,
            spacing: 12
        )
    }
}

// MARK: - Text fields:

private extension PasswordResetFourView {
    private var textFields: some View {
        VStack(
            alignment: .leading,
            spacing: spacing
        ) {
            textFieldsContent
        }
    }
    
    @ViewBuilder
    private var textFieldsContent: some View {
        emailAddressTextField
        newPasswordContent
    }
    
    private var emailAddressTextField: some View {
        TextFieldView(
            text: $emailAddress,
            title: "Email Address",
            keyboardType: .emailAddress
        )
    }
}

// MARK: - New password:

private extension PasswordResetFourView {
    private var newPasswordContent: some View {
        VStack(
            alignment: .leading,
            spacing: newPasswordSpacing
        ) {
            newPasswordItem
        }
    }
    
    @ViewBuilder
    private var newPasswordItem: some View {
        SectionHeaderView(title: "New Password")
        newPasswordTextFields
    }
    
    private var newPasswordTextFields: some View {
        VStack(
            alignment: .leading,
            spacing: newPasswordSpacing
        ) {
            newPasswordTextFieldsContent
        }
    }
    
    @ViewBuilder
    private var newPasswordTextFieldsContent: some View {
        newPasswordTextField
        confirmedNewPasswordTextField
    }
    
    private var newPasswordTextField: some View {
        TextFieldView(
            text: $newPassword,
            title: "New Password",
            isSecure: true,
            minHeight: passwordTextFieldMinHeight
        )
    }
    
    private var confirmedNewPasswordTextField: some View {
        TextFieldView(
            text: $confirmedNewPassword,
            title: "Confirm New Password",
            isSecure: true,
            minHeight: passwordTextFieldMinHeight
        )
    }
}

// MARK: - Toolbar:

private extension PasswordResetFourView {
    private var toolbar: some View {
        BottomToolbarView() {
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
    PasswordResetFourView()
}
