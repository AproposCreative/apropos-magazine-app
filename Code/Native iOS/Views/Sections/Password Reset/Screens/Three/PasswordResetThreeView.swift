//
//  PasswordResetThreeView.swift
//  Native
//

import SwiftUI

struct PasswordResetThreeView: View {
    
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
            .background(imageContent)
            .toolbarButton(
                title: "Cancel",
                font: .body,
                color: .primary,
                placement: .cancellationAction,
                action: dismiss.callAsFunction
            )
            .animation(
                .default,
                value: isUpdatePasswordDisabled
            )
            .navigationStack()
            .darkColorScheme()
    }
}

// MARK: - Item:

private extension PasswordResetThreeView {
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

private extension PasswordResetThreeView {
    private var imageContent: some View {
        image
            .resizable()
            .ignoresSafeArea()
    }
}

// MARK: - Scroll:

private extension PasswordResetThreeView {
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

private extension PasswordResetThreeView {
    private var titleSubtitle: some View {
        TitleSubtitleView(
            title: "Password Reset",
            titleFont: .largeTitle.bold(),
            titleAlignment: .leading,
            subtitle: "Please enter and confirm your email address below in order to reset your password.",
            subtitleFont: .title3,
            subtitleAlignment: .leading,
            alignment: .leading,
            spacing: 16
        )
    }
}

// MARK: - Text fields:

private extension PasswordResetThreeView {
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
        newPasswordTextField
        confirmedNewPasswordTextField
    }
    
    private var emailAddressTextField: some View {
        TextFieldView(
            text: $emailAddress,
            title: "Email Address",
            keyboardType: .emailAddress,
            backgroundColor: textFieldBackground
        )
    }
    
    private var newPasswordTextField: some View {
        TextFieldView(
            text: $newPassword,
            title: "New Password",
            isSecure: true,
            minHeight: passwordTextFieldMinHeight,
            backgroundColor: textFieldBackground
        )
    }
    
    private var confirmedNewPasswordTextField: some View {
        TextFieldView(
            text: $confirmedNewPassword,
            title: "Confirm New Password",
            isSecure: true,
            minHeight: passwordTextFieldMinHeight,
            backgroundColor: textFieldBackground
        )
    }
}

// MARK: - Toolbar:

private extension PasswordResetThreeView {
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
    PasswordResetThreeView()
}
