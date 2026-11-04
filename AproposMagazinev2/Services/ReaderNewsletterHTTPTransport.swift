import Foundation

/// Exact endpoint allowlist, ephemeral HTTP and no redirect/credential forwarding.
@MainActor
struct ReaderNewsletterHTTPTransport {
    struct Credentials: Sendable {
        let idToken: String
        let appCheckToken: String
    }
    enum Failure: Error { case unavailable, invalidResponse }
    typealias Execute = (URLRequest) async throws -> (Data, HTTPURLResponse)
    let endpoint: URL
    let credentials: (CanonicalSessionState.ContextTicket) async throws -> Credentials
    let isCurrent: (CanonicalSessionState.ContextTicket) -> Bool
    let execute: Execute

    func send(_ payload: ReaderNewsletterSignupModel.Request,
              context: CanonicalSessionState.ContextTicket) async throws -> ReaderNewsletterSignupModel.Response {
        guard isCurrent(context), payload.expectedUserID == context.userID else { throw CancellationError() }
        guard payload.reconfirmationChallenge == nil || ReaderNewsletterSignupModel.validChallenge(payload.reconfirmationChallenge) else {
            throw Failure.invalidResponse
        }
        // The executor validates this same exact URL and forbids redirects.
        _ = try PushRegistrationURLSessionExecutor(allowedURLs: [endpoint])
        let tokens = try await credentials(context)
        try Task.checkCancellation()
        guard isCurrent(context), !tokens.idToken.isEmpty, !tokens.appCheckToken.isEmpty else { throw CancellationError() }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + tokens.idToken, forHTTPHeaderField: "Authorization")
        request.setValue(tokens.appCheckToken, forHTTPHeaderField: "X-Firebase-AppCheck")
        request.httpBody = try JSONEncoder().encode(payload)
        guard isCurrent(context) else { throw CancellationError() }
        let (data, response) = try await execute(request)
        try Task.checkCancellation()
        guard isCurrent(context) else { throw CancellationError() }
        guard response.url == endpoint, response.statusCode == 200, data.count <= 16_384,
              response.mimeType?.lowercased() == "application/json" else { throw Failure.invalidResponse }
        let result = try JSONDecoder().decode(ReaderNewsletterSignupModel.Response.self, from: data)
        guard result.requestID == payload.requestID else { throw Failure.invalidResponse }
        return result
    }
}
