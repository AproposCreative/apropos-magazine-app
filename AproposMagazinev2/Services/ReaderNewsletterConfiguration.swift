import Foundation

enum ReaderNewsletterConfiguration {
    /// Validation only: the executor constructor opens no session or service.
    static func endpoint(in info: [String: Any]) -> URL? {
        guard info["ReaderNewsletterEnabled"] as? Bool == true,
              let address = info["ReaderNewsletterEndpoint"] as? String,
              let endpoint = URL(string: address),
              (try? PushRegistrationURLSessionExecutor(allowedURLs: [endpoint])) != nil else { return nil }
        return endpoint
    }
}
