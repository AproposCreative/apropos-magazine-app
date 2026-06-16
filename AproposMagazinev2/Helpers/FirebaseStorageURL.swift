import Foundation

/// Builds Firebase Storage media URLs without embedding download tokens in source.
enum FirebaseStorageURL {
    static let bucket = "apropos-magazine-6004a.firebasestorage.app"

    static func mediaURL(storagePath: String, downloadToken: String? = nil) -> URL? {
        let encoded = encodePath(storagePath)
        var urlString = "https://firebasestorage.googleapis.com/v0/b/\(bucket)/o/\(encoded)?alt=media"
        if let token = downloadToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            urlString += "&token=\(token)"
        }
        return URL(string: urlString)
    }

    private static func encodePath(_ path: String) -> String {
        path
            .split(separator: "/")
            .map { segment in
                segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(segment)
            }
            .joined(separator: "%2F")
    }
}
