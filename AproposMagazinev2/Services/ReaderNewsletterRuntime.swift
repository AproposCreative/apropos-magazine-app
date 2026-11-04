import Foundation
import FirebaseAuth
import FirebaseAppCheck

/// Construction is inert. Production activation needs a reviewed endpoint and
/// App Check configuration; unit/smoke modes never access either SDK or network.
@MainActor
enum ReaderNewsletterRuntime {
    static let model = ReaderNewsletterSignupModel(canonical: AuthService.shared.state, send: send)

    private static func send(_ payload: ReaderNewsletterSignupModel.Request,
                             context: CanonicalSessionState.ContextTicket) async throws -> ReaderNewsletterSignupModel.Response {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              !LocalSmokeMode.isEnabled,
              let endpoint = ReaderNewsletterConfiguration.endpoint(in: Bundle.main.infoDictionary ?? [:]) else {
            return .init(status: .unavailable, requestID: payload.requestID)
        }
        let executor = try PushRegistrationURLSessionExecutor(allowedURLs: [endpoint])
        let current: (CanonicalSessionState.ContextTicket) -> Bool = { original in
            let auth = AuthService.shared
            guard auth.isCurrent(original), let user = Auth.auth().currentUser else { return false }
            return user.uid == payload.expectedUserID && user.email == payload.expectedEmail
                && user.isEmailVerified && auth.state.isCurrent(original)
        }
        let transport = ReaderNewsletterHTTPTransport(endpoint: endpoint, credentials: { original in
            try await ReaderNewsletterCredentialDeadline.run {
                try Task.checkCancellation()
                guard current(original), let user = Auth.auth().currentUser else { throw CancellationError() }
                let token = try await user.getIDToken(forcingRefresh: true)
                try Task.checkCancellation()
                guard current(original) else { throw CancellationError() }
                let attestation = try await AppCheck.appCheck().limitedUseToken()
                try Task.checkCancellation()
                guard current(original) else { throw CancellationError() }
                return ReaderNewsletterHTTPTransport.Credentials(idToken: token, appCheckToken: attestation.token)
            }
        }, isCurrent: current, execute: { try await executor.perform($0) })
        return try await transport.send(payload, context: context)
    }
}
