import Foundation

/// Fixed support destination and bounded handoff policies. This never sends mail,
/// adds account/device details, or truncates the reader's draft.
enum SupportContactPolicy {
    static let recipient = "support@aproposmagazine.com"
    static let subject = "Hjælp til Apropos Magazine"
    static let maximumMailtoBytes = 2_048
    static let maximumComposerBodyBytes = 65_536

    static func isMeaningfulMessage(_ message: String) -> Bool {
        message.unicodeScalars.contains { !CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    static func canPresentComposer(body: String) -> Bool {
        isMeaningfulMessage(body) && body.utf8.count <= maximumComposerBodyBytes
    }

    static func mailtoURL(body: String) -> URL? {
        guard isMeaningfulMessage(body),
              let encodedSubject = encoded(subject, budget: maximumMailtoBytes) else { return nil }
        let prefix = "mailto:\(recipient)?subject=\(encodedSubject)&body="
        guard prefix.utf8.count < maximumMailtoBytes,
              let encodedBody = encoded(body, budget: maximumMailtoBytes - prefix.utf8.count) else { return nil }
        return URL(string: prefix + encodedBody)
    }

    /// Only RFC 3986 unreserved bytes remain literal. In particular '+' cannot
    /// become a space, and message text cannot inject recipients/query parameters.
    private static func encoded(_ text: String, budget: Int) -> String? {
        let hex = Array("0123456789ABCDEF".utf8)
        var result: [UInt8] = []
        result.reserveCapacity(budget)
        for byte in text.utf8 {
            let unreserved = (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
                || byte == 45 || byte == 46 || byte == 95 || byte == 126
            let size = unreserved ? 1 : 3
            guard result.count <= budget - size else { return nil }
            if unreserved { result.append(byte) }
            else { result.append(37);result.append(hex[Int(byte >> 4)]);result.append(hex[Int(byte & 15)]) }
        }
        return String(decoding: result, as: UTF8.self)
    }
}
