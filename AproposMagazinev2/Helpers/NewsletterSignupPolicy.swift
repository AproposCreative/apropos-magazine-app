import Foundation

/// The existing Webflow form feeds Apropos AI's Webflow → Resend pipeline.
/// Account email stays out of the URL, history, analytics and referrer headers.
enum NewsletterSignupPolicy {
    static let formURL = URL(string: "https://www.aproposmagazine.com/#Subscribe-Footer")
    static func termsURL(for language: ArticleContentLanguage) -> URL? {
        let path = language == .english ? "/en/other/legal" : "/other/legal"
        return URL(string: "https://www.aproposmagazine.com" + path)
    }

    static func canPrefill(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" && url.host == "www.aproposmagazine.com"
            && (url.path.isEmpty || url.path == "/")
            && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }

    static func prefillScript(email: String) -> String? {
        guard email.count <= 254,
              let data = try? JSONSerialization.data(withJSONObject: [email]),
              let literal = String(data: data, encoding: .utf8) else { return nil }
        return """
        (() => {
          if (location.protocol !== 'https:' || location.hostname !== 'www.aproposmagazine.com' || location.pathname !== '/') return false;
          const form = document.getElementById('Subscribe-Footer');
          const input = form && form.querySelector('input[type="email"]');
          if (!input) return false;
          if (!input.value) {
            input.value = \(literal)[0];
            input.dispatchEvent(new Event('input', { bubbles: true }));
            input.dispatchEvent(new Event('change', { bubbles: true }));
          }
          form.scrollIntoView({ block: 'center' });
          return true;
        })()
        """
    }
}
