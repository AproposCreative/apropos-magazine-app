import Combine
import Foundation

/// Local consistency policy. No player, services, persistence singleton or network.
@MainActor
final class PodcastAvailabilityModel {
    struct MediaBinding: Codable, Equatable {
        struct Recording: Codable, Equatable { let articleSlug: String? }
        let articleID: String?
        let isAINarration: Bool
        let sourceRevision: String?
        /// The v1 producer supplied an article slug but no canonical/source fields.
        /// Keep that accepted slug so enrichment cannot substitute another story.
        let legacyArticleSlug: String?
        /// Present only for an accepted, unambiguous raw unversioned row. Old
        /// snapshots may retain streaming compatibility without this new proof.
        let recording: Recording?
        var isLegacyNarration: Bool { isAINarration && articleID == nil && sourceRevision == nil }
        init(_ episode: PodcastEpisode, acceptsRecording: Bool = true) {
            articleID = episode.articleId
            isAINarration = episode.isAINarration
            sourceRevision = episode.sourceContentRevision
            let slug = episode.articleSlug?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            legacyArticleSlug = episode.isAINarration && episode.articleId == nil && episode.sourceContentRevision == nil
                ? slug.flatMap { $0.isEmpty ? nil : $0 } : nil
            recording = acceptsRecording && episode.sourceContentRevision == nil
                ? Recording(articleSlug: slug.flatMap { $0.isEmpty ? nil : $0 }) : nil
        }
    }
    struct Snapshot: Codable {
        var aliasesByID: [String: Set<String>] = [:]
        var revokedKeys: Set<String> = []
        /// nil means no accepted manifest; an empty set means authoritative empty.
        var manifestKeys: Set<String>? = nil
        /// Added in 1.16. Older snapshots retain every denial and membership.
        var manifestBindings: [String: MediaBinding]? = nil
        init() {}
        enum CodingKeys: String, CodingKey { case aliasesByID, revokedKeys, manifestKeys, manifestBindings }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            aliasesByID = try container.decodeIfPresent([String: Set<String>].self, forKey: .aliasesByID) ?? [:]
            revokedKeys = try container.decodeIfPresent(Set<String>.self, forKey: .revokedKeys) ?? []
            manifestKeys = try container.decodeIfPresent(Set<String>.self, forKey: .manifestKeys)
            manifestBindings = try container.decodeIfPresent([String: MediaBinding].self, forKey: .manifestBindings)
        }
    }
    struct PlaybackPlan {
        let queue: [PodcastEpisode]
        let stopCurrent: Bool
    }
    struct ArticleAudio: Hashable {
        let articleID: String
        let url: URL
    }
    private(set) var snapshot: Snapshot
    private(set) var withdrawnIDs: Set<String>
    private var playbackArticleIDs: [String: String] = [:]
    private var knownEpisodes: [String: PodcastEpisode] = [:]
    // Immutable process observations survive id+URL replacement. They are
    // cleanup evidence only, never accepted manifest/member authority.
    nonisolated static let maximumObservedAudioAssets = 512
    private(set) var offlineAssetEvidenceExhausted = false
    private var observedAudioAssets = Set<PodcastAudioAsset>()
    private let approvedRevision: (String) -> String?
    private let wasInvalidated: (String) -> Bool
    private let save: (Snapshot) -> Void
    private let subject = PassthroughSubject<Void, Never>()
    var changes: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }

    init(snapshot: Snapshot = .init(), withdrawnIDs: Set<String> = [],
         approvedRevision: @escaping (String) -> String? = { _ in nil },
         wasInvalidated: @escaping (String) -> Bool = { _ in false },
         save: @escaping (Snapshot) -> Void = { _ in }) {
        self.snapshot = snapshot
        self.withdrawnIDs = withdrawnIDs
        self.approvedRevision = approvedRevision
        self.wasInvalidated = wasInvalidated
        self.save = save
    }

    static func key(_ episode: PodcastEpisode) -> String {
        // Keep the old key: adding source metadata must never evade a revocation.
        "\(episode.id.utf8.count):\(episode.id)\(episode.audioURL?.absoluteString ?? "")"
    }

    func recordIdentities(_ identities: [(id: String, slug: String?)]) {
        var changed = false
        for identity in identities where CMSMirrorDocumentPolicy.isSafeDocumentID(identity.id) {
            guard let slug = normalized(identity.slug) else { continue }
            if snapshot.aliasesByID[identity.id, default: []].insert(slug).inserted { changed = true }
        }
        if changed { revokeKnownWithdrawn(); publish() }
    }

    func recordEpisodes(_ episodes: [PodcastEpisode]) {
        var changed = false
        for episode in episodes where matchesObservedBinding(episode) {
            let key = Self.key(episode)
            if knownEpisodes[key] != episode { changed = true; knownEpisodes[key] = episode }
        }
        if revokeKnownWithdrawn() { publish() }
        else if changed { subject.send(()) }
    }

    func recordPlayback(_ episode: PodcastEpisode, articleID: String?) {
        guard Self.hasConsistentIdentity(episode, articleID: articleID), matchesObservedBinding(episode, articleID: articleID) else { return }
        let key = Self.key(episode)
        let changed = knownEpisodes[key] != episode || playbackArticleIDs[key] != articleID
        knownEpisodes[key] = episode
        if let articleID { playbackArticleIDs[key] = articleID }
        if revokeKnownWithdrawn() { publish() }
        else if changed { subject.send(()) }
    }

    /// Article authority is injected, never copied into a second revision ledger.
    func refreshArticleRevisions() { subject.send(()) }

    func setWithdrawn(_ ids: Set<String>) {
        guard ids != withdrawnIDs else { return }
        withdrawnIDs = ids
        revokeKnownWithdrawn()
        publish() // Synchronous: withdrawal cannot coalesce with republication.
    }

    func seedCachedManifest(_ episodes: [PodcastEpisode]) {
        guard let acceptedKeys = snapshot.manifestKeys else {
            acceptManifest(episodes)
            return
        }
        // Upgrade only missing slug metadata from an already accepted v1 key.
        // Old cache must never add membership, replace v2 proof or erase a denial.
        guard var bindings = snapshot.manifestBindings else { return }
        let grouped = Dictionary(grouping: episodes, by: Self.key)
        var changed = false
        for (key, candidates) in grouped where acceptedKeys.contains(key) && candidates.count == 1 {
            guard let old = bindings[key], old.isLegacyNarration, old.legacyArticleSlug == nil,
                  let episode = candidates.first else { continue }
            let cached = MediaBinding(episode, acceptsRecording: false)
            guard cached.isLegacyNarration, cached.legacyArticleSlug != nil else { continue }
            bindings[key] = cached
            changed = true
        }
        if changed { snapshot.manifestBindings = bindings; publish() }
    }

    func acceptManifest(_ episodes: [PodcastEpisode]) {
        let groups = Dictionary(grouping: episodes, by: Self.key)
        let bindings = groups.mapValues { values in MediaBinding(values.last!, acceptsRecording: values.count == 1) }
        let keys = Set(episodes.map(Self.key))
        let changed = snapshot.manifestKeys != keys || snapshot.manifestBindings != bindings
        snapshot.manifestKeys = keys
        snapshot.manifestBindings = bindings
        for episode in episodes {
            let key = Self.key(episode)
            knownEpisodes[key] = episode
            if let id = episode.articleId, playbackArticleIDs[key] != id { playbackArticleIDs.removeValue(forKey: key) }
        }
        let revoked = revokeKnownWithdrawn()
        if changed || revoked { publish() }
    }

    nonisolated static func hasConsistentIdentity(_ episode: PodcastEpisode, articleID: String?) -> Bool {
        let values = [articleID, episode.articleId].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return values.allSatisfy(CMSMirrorDocumentPolicy.isSafeDocumentID) && Set(values).count <= 1
    }

    func allows(_ episode: PodcastEpisode, articleID: String? = nil) -> Bool {
        let key = Self.key(episode)
        guard Self.hasConsistentIdentity(episode, articleID: articleID), !snapshot.revokedKeys.contains(key),
              !isWithdrawn(episode, articleID: articleID),
              snapshot.manifestKeys.map({ $0.contains(key) }) ?? true,
              matchesAcceptedBinding(episode, articleID: articleID) else { return false }
        guard episode.isAINarration else { return true }
        guard let binding = snapshot.manifestBindings?[key], binding.isAINarration else { return false }
        // v1 narration remains streamable without pretending it has v2 source
        // proof. Exact accepted slug/identity and all denials were checked above.
        if binding.isLegacyNarration { return true }
        // An explicit raw canonical ID can associate an existing recording
        // without asserting that it narrates a particular CMS text revision.
        if binding.sourceRevision == nil, binding.recording != nil {
            return recordingAsset(episode, binding: binding, articleID: articleID) != nil
        }
        guard let id = binding.articleID, CMSMirrorDocumentPolicy.isSafeDocumentID(id),
              let revision = binding.sourceRevision, Self.isCMSRevision(revision) else { return false }
        if let approved = approvedRevision(id) { return revision == approved }
        return !wasInvalidated(id)
    }

    func unavailableMessage(for episode: PodcastEpisode, articleID: String? = nil) -> String {
        if episode.isAINarration, !isWithdrawn(episode, articleID: articleID) {
            return "AI-oplæsningens kilde kan ikke bekræftes. Prøv igen senere."
        }
        return "Lyden er ikke længere tilgængelig."
    }

    private static func isCMSRevision(_ value: String) -> Bool {
        let prefix = "cms-sha256-v1:"
        guard value.hasPrefix(prefix) else { return false }
        let bytes = value.dropFirst(prefix.count).utf8
        return bytes.count == 64 && bytes.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private func matchesObservedBinding(_ episode: PodcastEpisode, articleID: String? = nil) -> Bool {
        guard matchesAcceptedBinding(episode, articleID: articleID) else { return false }
        guard let binding = snapshot.manifestBindings?[Self.key(episode)] else { return true }
        // A stale human streaming DTO must not replace the accepted r2
        // descriptor used by cleanup merely because its URL is unchanged.
        guard binding.sourceRevision == episode.sourceContentRevision else { return false }
        return binding.recording.map { $0.articleSlug == normalized(episode.articleSlug) } ?? true
    }

    private func matchesAcceptedBinding(_ episode: PodcastEpisode, articleID: String? = nil) -> Bool {
        guard let binding = snapshot.manifestBindings?[Self.key(episode)] else { return true }
        guard binding.isAINarration == episode.isAINarration else { return false }
        if binding.isLegacyNarration {
            return matchesLegacyNarration(binding, episode: episode, articleID: articleID)
        }
        if let canonical = binding.articleID, canonical != (episode.articleId ?? articleID) { return false }
        return !binding.isAINarration || (binding.articleID == episode.articleId && binding.sourceRevision == episode.sourceContentRevision)
    }

    private func matchesLegacyNarration(_ binding: MediaBinding, episode: PodcastEpisode, articleID: String?) -> Bool {
        guard episode.sourceContentRevision == nil,
              let slug = binding.legacyArticleSlug, normalized(episode.articleSlug) == slug else { return false }
        let matchingIDs = snapshot.aliasesByID.filter { $0.value.contains(slug) }.map(\.key)
        guard matchingIDs.count <= 1 else { return false }
        if let canonical = episode.articleId ?? articleID {
            guard matchingIDs.first == canonical else { return false }
        }
        // A formerly withdrawn story cannot regain its unversioned audio merely
        // by being republished or reappearing in an old cached manifest.
        return matchingIDs.allSatisfy { !withdrawnIDs.contains($0) && !wasInvalidated($0) }
    }

    /// Producer proof and accepted-recording association are distinct. Neither
    /// a caller's enrichment nor the current saved text can invent either one.
    func audioAsset(for episode: PodcastEpisode, articleID: String? = nil, allowsAcceptedRecording: Bool = true) -> PodcastAudioAsset? {
        guard !offlineAssetEvidenceExhausted, allows(episode, articleID: articleID),
              let asset = boundAsset(episode, articleID: articleID),
              allowsAcceptedRecording || asset.sourceRevision != nil else { return nil }
        if let approved = approvedRevision(asset.canonicalArticleID), !asset.isCompatible(withTextRevision: approved) { return nil }
        knownEpisodes[Self.key(episode)] = episode
        let exhausted = rememberAsset(asset)
        if exhausted { subject.send(()) }
        return offlineAssetEvidenceExhausted ? nil : asset
    }

    var availableAudioAssets: Set<PodcastAudioAsset> {
        guard !offlineAssetEvidenceExhausted else { return [] }
        return Set(observedAudioAssets.filter { asset in
            let key = "\(asset.episodeID.utf8.count):\(asset.episodeID)\(asset.remoteURL.absoluteString)"
            guard let episode = knownEpisodes[key], allows(episode, articleID: asset.canonicalArticleID),
                  boundAsset(episode, articleID: asset.canonicalArticleID) == asset else { return false }
            return approvedRevision(asset.canonicalArticleID).map { asset.isCompatible(withTextRevision: $0) } ?? true
        })
    }

    var unavailableAudioAssets: Set<PodcastAudioAsset> {
        observedAudioAssets.subtracting(availableAudioAssets)
    }

    private func boundAsset(_ episode: PodcastEpisode, articleID: String? = nil) -> PodcastAudioAsset? {
        guard let binding = snapshot.manifestBindings?[Self.key(episode)],
              snapshot.manifestKeys?.contains(Self.key(episode)) == true,
              binding.isAINarration == episode.isAINarration else { return nil }
        if binding.sourceRevision == nil, episode.sourceContentRevision == nil {
            return recordingAsset(episode, binding: binding, articleID: articleID)
        }
        guard
              let canonical = episode.articleId, CMSMirrorDocumentPolicy.isSafeDocumentID(canonical),
              articleID.map({ $0 == canonical }) ?? true, binding.articleID == canonical,
              binding.isAINarration == episode.isAINarration,
              let revision = episode.sourceContentRevision, binding.sourceRevision == revision,
              !episode.isAINarration || Self.isCMSRevision(revision), let url = episode.audioURL else { return nil }
        return PodcastAudioAsset(episodeID: episode.id, canonicalArticleID: canonical,
            kind: episode.isAINarration ? .ai : .human, sourceRevision: revision, remoteURL: url)
    }

    private func recordingAsset(_ episode: PodcastEpisode, binding: MediaBinding, articleID: String?) -> PodcastAudioAsset? {
        guard let recording = binding.recording, binding.sourceRevision == nil, episode.sourceContentRevision == nil,
              normalized(episode.articleSlug) == recording.articleSlug,
              Self.hasConsistentIdentity(episode, articleID: articleID), let url = episode.audioURL else { return nil }
        let canonical: String
        if let rawID = binding.articleID {
            guard CMSMirrorDocumentPolicy.isSafeDocumentID(rawID), episode.articleId == rawID,
                  articleID.map({ $0 == rawID }) ?? true else { return nil }
            canonical = rawID
        } else {
            guard let slug = recording.articleSlug else { return nil }
            let identities = snapshot.aliasesByID.filter { $0.value.contains(slug) }.map(\.key)
            guard identities.count == 1, let unique = identities.first,
                  !ArticleContentLanguage.isEnglishArticleID(unique),
                  (episode.articleId ?? articleID).map({ $0 == unique }) ?? true else { return nil }
            canonical = unique
        }
        guard !withdrawnIDs.contains(canonical), !wasInvalidated(canonical) else { return nil }
        return PodcastAudioAsset(episodeID: episode.id, canonicalArticleID: canonical,
            kind: episode.isAINarration ? .ai : .human, acceptedRecordingArticleID: binding.articleID,
            acceptedRecordingSlug: recording.articleSlug, remoteURL: url)
    }

    /// Never prune old cleanup evidence. Exhaustion closes offline admission
    /// for this model lifetime; all previously admitted descriptors stay denied.
    @discardableResult private func rememberAsset(_ asset: PodcastAudioAsset) -> Bool {
        guard !offlineAssetEvidenceExhausted, !observedAudioAssets.contains(asset) else { return false }
        guard observedAudioAssets.count < Self.maximumObservedAudioAssets else {
            offlineAssetEvidenceExhausted = true
            return true
        }
        observedAudioAssets.insert(asset)
        return false
    }

    var availableAudioURLs: Set<URL> {
        Set(knownEpisodes.values.filter { allows($0) }.compactMap(\.audioURL))
    }

    var unavailableAudioURLs: Set<URL> {
        Set(knownEpisodes.values.filter { !allows($0) }.compactMap(\.audioURL)).subtracting(availableAudioURLs)
    }

    var unavailableArticleAudio: Set<ArticleAudio> {
        Set(knownEpisodes.compactMap { key, episode -> ArticleAudio? in
            guard !allows(episode, articleID: playbackArticleIDs[key]), let url = episode.audioURL else { return nil }
            let explicitID = episode.articleId ?? playbackArticleIDs[key]
            let aliases = Set([normalized(episode.articleSlug), normalized(episode.id)].compactMap { $0 })
            let matchingIDs = snapshot.aliasesByID.filter { !$0.value.isDisjoint(with: aliases) }.map(\.key)
            guard let id = explicitID ?? (matchingIDs.count == 1 ? matchingIDs.first : nil),
                  CMSMirrorDocumentPolicy.isSafeDocumentID(id) else { return nil }
            return ArticleAudio(articleID: id, url: url)
        })
    }

    func playbackPlan(current: PodcastEpisode?, articleID: String?, queue: [PodcastEpisode]) -> PlaybackPlan {
        PlaybackPlan(queue: queue.filter { allows($0) }, stopCurrent: current.map { !allows($0, articleID: articleID) } ?? false)
    }

    private func isWithdrawn(_ episode: PodcastEpisode, articleID: String? = nil) -> Bool {
        let explicit = [articleID, episode.articleId].compactMap { value -> String? in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
        if !explicit.isEmpty {
            return explicit.contains { !CMSMirrorDocumentPolicy.isSafeDocumentID($0) || withdrawnIDs.contains($0) }
        }
        if withdrawnIDs.contains(episode.id) { return true }
        let aliases = Set([normalized(episode.articleSlug), normalized(episode.id)].compactMap { $0 })
        return withdrawnIDs.contains { !(snapshot.aliasesByID[$0] ?? []).isDisjoint(with: aliases) }
    }

    @discardableResult
    private func revokeKnownWithdrawn() -> Bool {
        var changed = false
        for (key, episode) in knownEpisodes where isWithdrawn(episode, articleID: playbackArticleIDs[key]) {
            if snapshot.revokedKeys.insert(key).inserted { changed = true }
        }
        return changed
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let slug = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return slug.isEmpty ? nil : slug
    }

    private func publish() { save(snapshot); subject.send(()) }
}
