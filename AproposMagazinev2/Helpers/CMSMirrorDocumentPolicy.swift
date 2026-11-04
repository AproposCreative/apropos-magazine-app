import Foundation

/// Explicit withdrawals must be handled before decoding stripped tombstone data.
/// Legacy metadata without publication flags remains readable until its inventory
/// and ownership migration has been approved.
enum CMSMirrorDocumentPolicy {
    /// Safe single Firestore document ID, including legacy slugs. Never accept
    /// a document path from a deep link or a user-editable favorite payload.
    static func isSafeDocumentID(_ id: String) -> Bool {
        !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        id.utf8.count <= 1500 && !id.contains("/") && id != "." && id != ".." &&
        !(id.count >= 4 && id.hasPrefix("__") && id.hasSuffix("__")) &&
        id.rangeOfCharacter(from: .controlCharacters) == nil
    }

    static func isWithdrawn(_ data: [String: Any]) -> Bool {
        data["publicationState"] as? String == "withdrawn" ||
        data["isDraft"] as? Bool == true || data["isArchived"] as? Bool == true
    }
}
