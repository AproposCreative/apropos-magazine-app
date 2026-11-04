import CryptoKit
import Foundation

/// An accepted recording identity is separate from a producer's source proof.
/// Neither grants membership nor claims what the received audio actually says.
struct PodcastAudioAsset: Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable { case human, ai }
    enum Binding: Hashable, Sendable {
        case producerSource(String)
        case acceptedRecording(articleID: String?, articleSlug: String?)
    }
    let episodeID: String
    let canonicalArticleID: String
    let kind: Kind
    let binding: Binding
    var sourceRevision: String? {
        if case .producerSource(let revision) = binding { return revision }
        return nil
    }
    let remoteURL: URL
    let key: String
    init?(episodeID: String, canonicalArticleID: String, kind: Kind, sourceRevision: String, remoteURL: URL) {
        self.init(episodeID: episodeID, canonicalArticleID: canonicalArticleID, kind: kind,
            binding: .producerSource(sourceRevision), remoteURL: remoteURL)
    }
    init?(episodeID: String, canonicalArticleID: String, kind: Kind, acceptedRecordingArticleID: String?,
          acceptedRecordingSlug: String?, remoteURL: URL) {
        self.init(episodeID: episodeID, canonicalArticleID: canonicalArticleID, kind: kind,
            binding: .acceptedRecording(articleID: acceptedRecordingArticleID, articleSlug: acceptedRecordingSlug), remoteURL: remoteURL)
    }
    private init?(episodeID: String, canonicalArticleID: String, kind: Kind, binding: Binding, remoteURL: URL) {
        guard Self.validID(episodeID), Self.validID(canonicalArticleID),
              remoteURL.absoluteString.utf8.count <= 4096,
              let parts = URLComponents(url: remoteURL, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", parts.user == nil, parts.password == nil,
              parts.fragment == nil, parts.host?.isEmpty == false,
              remoteURL.pathExtension.lowercased() != "m3u8", PodcastAudioURLValidator.isPlayableAudioURL(remoteURL) else { return nil }
        self.episodeID = episodeID;self.canonicalArticleID = canonicalArticleID
        self.kind = kind;self.binding = binding;self.remoteURL = remoteURL
        let fields: [String]
        switch binding {
        case .producerSource(let revision):
            guard Self.validText(revision, limit: 1024) else { return nil }
            // Existing v2 identities and receipts retain their exact keys.
            fields = ["apropos/audio-asset/v2", episodeID, canonicalArticleID, kind.rawValue, revision, remoteURL.absoluteString]
        case .acceptedRecording(let articleID, let slug):
            guard articleID.map({ Self.validID($0) && $0 == canonicalArticleID }) ?? true,
                  slug.map({ Self.validText($0, limit: 1024) && $0 == $0.lowercased() }) ?? true,
                  articleID != nil || (slug != nil && !ArticleContentLanguage.isEnglishArticleID(canonicalArticleID)) else { return nil }
            fields = ["apropos/accepted-recording/v1", episodeID, canonicalArticleID, kind.rawValue,
                articleID.map { "id:" + $0 } ?? "no-id", slug.map { "slug:" + $0 } ?? "no-slug", remoteURL.absoluteString]
        }
        key = SHA256.hash(data: Data(fields.map { "\($0.utf8.count):\($0)" }.joined().utf8)).map { String(format: "%02x", $0) }.joined()
    }
    /// The text is independently checked by the current access ticket. Only a
    /// producer-source binding asserts that its recording belongs to that revision.
    func isCompatible(withTextRevision revision: String?) -> Bool {
        switch binding {
        case .producerSource(let source): return source == revision
        case .acceptedRecording: return revision?.isEmpty == false
        }
    }
    private struct Recording: Codable { let articleID: String?; let articleSlug: String? }
    private enum CodingKeys: String, CodingKey { case episodeID, canonicalArticleID, kind, sourceRevision, acceptedRecording, remoteURL }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let binding: Binding
        if c.contains(.acceptedRecording) {
            guard !c.contains(.sourceRevision) else { throw PodcastAudioReceipt.Failure.invalid }
            let recording = try c.decode(Recording.self, forKey: .acceptedRecording)
            binding = .acceptedRecording(articleID: recording.articleID, articleSlug: recording.articleSlug)
        } else { binding = .producerSource(try c.decode(String.self, forKey: .sourceRevision)) }
        guard let value = Self(episodeID: try c.decode(String.self, forKey: .episodeID),
            canonicalArticleID: try c.decode(String.self, forKey: .canonicalArticleID), kind: try c.decode(Kind.self, forKey: .kind),
            binding: binding, remoteURL: try c.decode(URL.self, forKey: .remoteURL)) else { throw PodcastAudioReceipt.Failure.invalid }
        self = value
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(episodeID, forKey: .episodeID);try c.encode(canonicalArticleID, forKey: .canonicalArticleID)
        try c.encode(kind, forKey: .kind);try c.encode(remoteURL, forKey: .remoteURL)
        switch binding {
        case .producerSource(let revision): try c.encode(revision, forKey: .sourceRevision)
        case .acceptedRecording(let articleID, let slug):
            try c.encode(Recording(articleID: articleID, articleSlug: slug), forKey: .acceptedRecording)
        }
    }
    private static func validText(_ text: String, limit: Int) -> Bool {
        !text.isEmpty && text.utf8.count <= limit && text == text.trimmingCharacters(in: .whitespacesAndNewlines)
            && !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
    private static func validID(_ text: String) -> Bool {
        validText(text, limit: 512) && !text.contains("/") && text != "." && text != ".."
            && !(text.hasPrefix("__") && text.hasSuffix("__"))
    }
}

/// A local integrity receipt. Its SHA describes the received file; it is not an
/// expected server digest and must never be presented as remote attestation.
struct PodcastAudioReceipt: Codable, Equatable, Sendable {
    enum Failure: Error { case invalid }
    static let maximumBytes = 16_384
    static let maximumAudioBytes: Int64 = 256 * 1024 * 1024
    let schemaVersion: Int
    let asset: PodcastAudioAsset
    let commitID: UUID
    let byteCount: Int64
    let sha256: String
    /// Absent on old v2 receipts: their existing .m4a paths are never renamed.
    let fileExtension: String?
    var fileName: String { asset.key + "-" + commitID.uuidString.lowercased() + "." + (fileExtension ?? "m4a") }
    init(asset: PodcastAudioAsset, commitID: UUID = UUID(), byteCount: Int64, sha256: String) throws {
        guard (1...Self.maximumAudioBytes).contains(byteCount), Self.validDigest(sha256) else { throw Failure.invalid }
        schemaVersion = 2;self.asset = asset;self.commitID = commitID;self.byteCount = byteCount;self.sha256 = sha256
        let suffix = asset.remoteURL.pathExtension.lowercased()
        guard Self.extensions.contains(suffix) else { throw Failure.invalid }
        fileExtension = suffix
    }
    func encoded() throws -> Data {
        let encoder = JSONEncoder();encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw Failure.invalid };return data
    }
    static func decode(_ data: Data, expectedAsset: PodcastAudioAsset) throws -> Self {
        guard !data.isEmpty, data.count <= maximumBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).subtracting(["fileExtension"]) == ["schemaVersion", "asset", "commitID", "byteCount", "sha256"],
              let fields = object["asset"] as? [String: Any],
              validAssetFields(fields),
              let receipt = try? JSONDecoder().decode(Self.self, from: data), receipt.schemaVersion == 2,
              receipt.asset == expectedAsset, (1...maximumAudioBytes).contains(receipt.byteCount), validDigest(receipt.sha256),
              receipt.fileExtension.map({ extensions.contains($0) }) ?? (object["fileExtension"] == nil) else { throw Failure.invalid }
        return receipt
    }
    static let extensions: Set<String> = ["mp3", "m4a", "aac", "wav", "mp4"]
    private static func validAssetFields(_ fields: [String: Any]) -> Bool {
        let base: Set<String> = ["episodeID", "canonicalArticleID", "kind", "remoteURL"]
        if Set(fields.keys) == base.union(["sourceRevision"]) { return true }
        guard Set(fields.keys) == base.union(["acceptedRecording"]), let recording = fields["acceptedRecording"] as? [String: Any] else { return false }
        return Set(recording.keys).isSubset(of: ["articleID", "articleSlug"])
    }
    private static func validDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
