import SwiftUI

/// Shared production form; operations are supplied by its model, never created here.
struct EmailAccountFormSections: View {
    @ObservedObject var form: EmailAccountFlowModel
    var providersWorking = false

    var body: some View {
        Group {
            Section(LocalizedStringKey(form.isReauthentication ? "Din konto" : "Fortsæt med e-mail")) {
                if let email = form.lockedEmail {
                    Text(email)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("account.lockedEmail")
                } else {
                    TextField("E-mail", text: $form.form.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("E-mail")
                        .accessibilityIdentifier("account.email")
                }
                if !form.isReauthentication && form.action == .signUp {
                    TextField("Navn (valgfrit)", text: $form.form.displayName)
                        .textContentType(.name)
                }
                if form.isReauthentication || form.action != .resetPassword {
                    SecureField("Adgangskode", text: $form.form.password)
                        .accessibilityLabel("Adgangskode")
                        .accessibilityIdentifier("account.password")
                        .textContentType(!form.isReauthentication && form.action == .signUp ? .newPassword : .password)
                }
                if !form.isReauthentication && form.action == .signUp {
                    SecureField("Gentag adgangskode", text: $form.form.confirmation)
                        .accessibilityLabel("Gentag adgangskode")
                        .accessibilityIdentifier("account.confirmation")
                        .textContentType(.newPassword)
                    Text("Brug mindst 8 tegn. Bekræft din e-mail efter oprettelsen.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error = form.errorMessage {
                    Text(LocalizedStringKey(error)).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("account.error")
                }
                if let status = form.statusMessage { Text(LocalizedStringKey(status)).foregroundStyle(.secondary).accessibilityIdentifier("account.status") }
                Button {
                    guard let submission = form.captureSubmission() else { return }
                    Task { await form.submit(submission) }
                } label: {
                    HStack {
                        Text(LocalizedStringKey(form.isReauthentication ? "Bekræft identitet" : form.action == .signUp ? "Opret konto" : form.action == .resetPassword ? "Send nulstillingsmail" : "Log ind"))
                        if form.isWorking { Spacer(); ProgressView() }
                    }
                }
                .accessibilityIdentifier("account.submit")
                .disabled(form.isWorking)
            }.disabled(form.isWorking || providersWorking)
            if !form.isReauthentication {
                Section {
                    Button(LocalizedStringKey(form.action == .signUp ? "Har du en konto? Log ind" : "Ny her? Opret med e-mail")) {
                        form.action = form.action == .signUp ? .signIn : .signUp
                    }
                    Button(LocalizedStringKey(form.action == .resetPassword ? "Tilbage til login" : "Glemt adgangskode?")) {
                        form.action = form.action == .resetPassword ? .signIn : .resetPassword
                    }
                }.disabled(form.isWorking || providersWorking)
            }
        }
        .tint(.primary)
        .onChange(of: form.action) { _, _ in form.clearFeedback() }
    }
}
