import Foundation
import ImageIO

/// Deterministic validation shared by the notification extension and unit tests.
enum NotificationImagePolicy {
    static let maximumBytes = 5 * 1024 * 1024
    static let requestTimeout: TimeInterval = 10
    static let resourceTimeout: TimeInterval = 12

    enum Format: Equatable {
        case jpeg, png, gif

        var fileExtension: String {
            switch self {
            case .jpeg: return "jpg"
            case .png: return "png"
            case .gif: return "gif"
            }
        }

        var typeIdentifier: String {
            switch self {
            case .jpeg: return "public.jpeg"
            case .png: return "public.png"
            case .gif: return "com.compuserve.gif"
            }
        }

        var mimeType: String {
            switch self {
            case .jpeg: return "image/jpeg"
            case .png: return "image/png"
            case .gif: return "image/gif"
            }
        }
    }

    static func isAllowedURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.isEmpty == false
            && url.user == nil
            && url.password == nil
    }

    static func allowsResponse(statusCode: Int, mimeType: String?, expectedLength: Int64) -> Bool {
        (200...299).contains(statusCode)
            && ["image/jpeg", "image/png", "image/gif"].contains(mimeType?.lowercased() ?? "")
            && (expectedLength == NSURLSessionTransferSizeUnknown
                || (expectedLength > 0 && expectedLength <= Int64(maximumBytes)))
    }

    static func validatedFormat(for data: Data, mimeType: String?) -> Format? {
        guard !data.isEmpty, data.count <= maximumBytes else { return nil }

        let format: Format
        if data.starts(with: [0xff, 0xd8, 0xff]) {
            format = .jpeg
        } else if data.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) {
            format = .png
        } else if data.starts(with: Data("GIF87a".utf8)) || data.starts(with: Data("GIF89a".utf8)) {
            format = .gif
        } else {
            return nil
        }

        // Confirm that the MIME, signature and parsed image all agree. Limit
        // image dimensions/frames without decoding a full bitmap in the extension.
        guard mimeType?.lowercased() == format.mimeType,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetType(source) as String? == format.typeIdentifier,
              (1...100).contains(CGImageSourceGetCount(source)),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              (1...4096).contains(width.intValue),
              (1...4096).contains(height.intValue) else {
            return nil
        }
        return format
    }
}
