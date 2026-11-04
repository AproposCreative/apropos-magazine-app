import Foundation

/// Public links describe an intent, never an audio URL or publication authority.
/// Podcast notification intents use nil for normal resume; URL timestamps retain
/// an explicit zero. Google OAuth URLs are handled by their separate adapter.
enum DeepLink: Equatable, Sendable {
    case article(id: String)
    case podcast(id: String, startSeconds: Int?)
    case category(name: String)
    case author(id: String)

    static let maximumURLBytes = 4096
    static let maximumIdentifierBytes = 512
    static let maximumStartSeconds = 7 * 24 * 60 * 60

    static func isValidIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumIdentifierBytes
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value != "." && value != ".."
            && !(value.hasPrefix("__") && value.hasSuffix("__"))
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && value.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\?#%")) == nil
    }
    var isValid: Bool {
        switch self {
        case .article(let id), .author(let id): return Self.isValidIdentifier(id)
        case .category(let name): return Self.isValidIdentifier(name)
        case .podcast(let id, let seconds):
            return Self.isValidIdentifier(id) && (seconds.map { (0...Self.maximumStartSeconds).contains($0) } ?? true)
        }
    }
    var supportsFallbackIdentifier: Bool {
        switch self { case .article, .podcast: return true; case .category, .author: return false }
    }
    var identifier: String {
        switch self {
        case .article(let id), .podcast(let id, _), .author(let id): return id
        case .category(let name): return name
        }
    }

    static func parse(_ url: URL) -> DeepLink? {
        guard url.absoluteString.utf8.count <= maximumURLBytes,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil, components.port == nil,
              let scheme = components.scheme?.lowercased() else { return nil }
        let host = components.host?.lowercased()
        let knownTypes: Set<String> = ["article", "category", "author"]
        let type: String
        let encodedIdentifier: String
        if scheme == "https" {
            guard ["aproposmagazine.com", "www.aproposmagazine.com"].contains(host ?? ""), components.fragment == nil,
                  let pair = pathPair(components.percentEncodedPath) else { return nil }
            type = pair.0; encodedIdentifier = pair.1
        } else if scheme == "aproposmagazine" {
            if let host, knownTypes.contains(host) {
                let segments = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
                guard components.fragment == nil, segments.count == 2, segments[0].isEmpty, !segments[1].isEmpty else { return nil }
                type = host; encodedIdentifier = String(segments[1])
            } else if host == "home", components.percentEncodedPath.isEmpty,
                      let fragment = components.percentEncodedFragment,
                      fragment.hasPrefix("article/"), fragment.split(separator: "/", omittingEmptySubsequences: false).count == 2 {
                type = "article"; encodedIdentifier = String(fragment.dropFirst("article/".count))
            } else if host == nil || host == "", components.fragment == nil,
                      let pair = pathPair(components.percentEncodedPath) {
                type = pair.0; encodedIdentifier = pair.1
            } else { return nil }
        } else { return nil }
        guard knownTypes.contains(type), let identifier = encodedIdentifier.removingPercentEncoding,
              isValidIdentifier(identifier) else { return nil }
        let timestamps = (components.queryItems ?? []).filter { $0.name == "t" }
        guard timestamps.count <= 1 else { return nil }
        var seconds: Int?
        if let item = timestamps.first {
            guard type == "article", let value = item.value, !value.isEmpty, value.utf8.count <= 6,
                  value.utf8.allSatisfy({ (48...57).contains($0) }), let number = Int(value),
                  (0...maximumStartSeconds).contains(number) else { return nil }
            seconds = number
        }
        switch type {
        case "article": return seconds.map { .podcast(id: identifier, startSeconds: $0) } ?? .article(id: identifier)
        case "category": return .category(name: identifier)
        case "author": return .author(id: identifier)
        default: return nil
        }
    }
    private static func pathPair(_ path: String) -> (String, String)? {
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.count == 3, segments[0].isEmpty, !segments[1].isEmpty, !segments[2].isEmpty else { return nil }
        return (String(segments[1]), String(segments[2]))
    }
}
