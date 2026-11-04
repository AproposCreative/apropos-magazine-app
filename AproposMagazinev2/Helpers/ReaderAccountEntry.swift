import Foundation

/// An immutable choice from one introduction. It is not a subscription receipt.
struct ReaderAccountEntry: Equatable {
    enum Provider: Equatable { case apple, google, email, emailSignIn, emailSignUp, account }
    let topicIDs: [String]
    let provider: Provider
    let newsletterOptIn: Bool

    /// Preserve the original introduction's `.email` signup behavior.
    var initialEmailAction: EmailAccountAction {
        switch provider {
        case .email, .emailSignUp: return .signUp
        default: return .signIn
        }
    }

    init(topicIDs: [String], provider: Provider = .account, newsletterOptIn: Bool = false) {
        self.topicIDs = ReaderPreferences(interestTopicIDs: topicIDs).interestTopicIDs
        self.provider = provider
        self.newsletterOptIn = newsletterOptIn
    }
}
