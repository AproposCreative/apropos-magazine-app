import Foundation

/// The actual recommendation consumer captures both committed projections in
/// one synchronous call. A mismatched or unresolved owner contributes no private
/// interests; a verified e-mail refresh never changes which account owns them.
/// A same-owner retry retains its last accepted load for stable recommendations,
/// while the preference model separately blocks writes until a fresh load passes.
struct ReaderRecommendationAccountInput: Equatable {
    let canonicalUserID: String?
    let canonicalGeneration: UUID
    let preferencesGeneration: UUID?
    let interestTopicIDs: [String]
}

@MainActor
enum ReaderRecommendationSelection {
    static func capture(canonical: CanonicalSessionState.Snapshot,
                        preferences: ReaderPreferencesModel.Snapshot,
                        guestInterestTopicIDs: [String] = []) -> ReaderRecommendationAccountInput {
        // Device-local interests are meaningful only while both committed
        // projections confirm guest. They are never a fallback for an account.
        if canonical.context == .guest, canonical.session == nil, preferences.context == .guest {
            return ReaderRecommendationAccountInput(canonicalUserID: nil,
                canonicalGeneration: canonical.generation, preferencesGeneration: nil,
                interestTopicIDs: normalizedGuestInterests(guestInterestTopicIDs))
        }
        let uid = canonical.session?.uid
        let matches = uid != nil && canonical.context.userID == uid && preferences.userID == uid
        let ready = matches && preferences.loadVersion != nil
        return ReaderRecommendationAccountInput(canonicalUserID: uid,
            canonicalGeneration: canonical.generation,
            preferencesGeneration: matches ? preferences.generation : nil,
            interestTopicIDs: ready ? Array(Set(preferences.preferences.interestTopicIDs)).sorted() : [])
    }

    private static func normalizedGuestInterests(_ ids: [String]) -> [String] {
        let valid = ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter {
            !$0.isEmpty && $0.utf8.count <= 128 && !$0.contains("/") && $0 != "." && $0 != ".."
                && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        }
        return Array(Set(valid).sorted().prefix(20))
    }
}
