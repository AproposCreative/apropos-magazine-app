import Foundation

struct ReaderAccountSession: Equatable {
    let uid: String
    let email: String
    let isEmailVerified: Bool
}

enum EmailAccountAction: Equatable { case signIn, signUp, resetPassword }

struct EmailAccountForm {
    var email = ""
    var password = ""
    var confirmation = ""
    var displayName = ""

    var normalizedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    func validationMessage(for action: EmailAccountAction) -> String? {
        let parts = normalizedEmail.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              parts[1].split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty }),
              !normalizedEmail.contains(where: { $0.isWhitespace }), normalizedEmail.count <= 254 else {
            return "Skriv en gyldig e-mailadresse."
        }
        if action == .resetPassword { return nil }
        guard !password.isEmpty else { return "Skriv din adgangskode." }
        if action == .signUp {
            guard password.count >= 8 else { return "Brug mindst 8 tegn i din adgangskode." }
            guard password == confirmation else { return "Adgangskoderne er ikke ens." }
            guard displayName.trimmingCharacters(in: .whitespacesAndNewlines).count <= 80 else {
                return "Navnet må højst være 80 tegn."
            }
        }
        return nil
    }
}

enum AccountErrorMessage {
    static func forError(_ error: Error) -> String {
        let code = (error as NSError).code
        switch code {
        case 17007, 17012, 17025:
            return "Adressen er allerede knyttet til en konto. Log ind med den metode, du brugte sidst."
        case 17008: return "Skriv en gyldig e-mailadresse."
        case 17009, 17011, 17004: return "Kunne ikke logge ind. Kontrollér e-mail og adgangskode."
        case 17020, NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut:
            return "Ingen forbindelse. Prøv igen, når du er online."
        case 17010: return "Der er forsøgt for mange gange. Vent lidt, og prøv igen."
        case 17026: return "Adgangskoden opfylder ikke kravene. Vælg en stærkere adgangskode."
        default: return "Handlingen kunne ikke gennemføres. Prøv igen."
        }
    }
}
