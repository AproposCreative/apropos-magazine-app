import Foundation

// Extension for chaining DateFormatter configuration
extension DateFormatter {
    func then(_ configure: (DateFormatter) -> Void) -> DateFormatter {
        configure(self)
        return self
    }
}

// Helper structs to decode the complex, polymorphic 'main-image' field from Webflow
fileprivate enum WebflowMedia: Decodable {
    case image(url: String)
    case video(thumbnailUrl: String)
    
    // Custom decoder to handle either an image object or a video object
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try decoding as a video first
        if let video = try? container.decode(VideoPayload.self) {
            self = .video(thumbnailUrl: video.thumbnailUrl)
            return
        }
        
        // Fallback to decoding as an image
        if let image = try? container.decode(ImagePayload.self) {
            self = .image(url: image.url)
            return
        }
        
        throw DecodingError.typeMismatch(WebflowMedia.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Media field was not a recognized type (image or video)."))
    }
    
    private struct ImagePayload: Decodable {
        let url: String
    }
    
    private struct VideoPayload: Decodable {
        let thumbnailUrl: String
    }
}

// Helper struct for assets like 'cover'
fileprivate struct WebflowAsset: Decodable {
    let url: String?
}

// Helper struct for video-trailer field from CMS
fileprivate struct VideoTrailerPayload: Decodable {
    let url: String?
    let metadata: VideoMetadata?
    
    struct VideoMetadata: Decodable {
        let width: Int?
        let height: Int?
        let html: String?
    }
}

struct Article: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String?
    let slug: String?
    let content: String?
    // Raw trailer field from CMS. Can be a URL (e.g. YouTube) or an embed HTML snippet
    let trailer: String?
    let intro: String?
    let stjerne: Int? // Number felt fra Webflow CMS
    let topicID: String?
    let topicsIDs: [String]?
    let authorID: String?
    let thumbURL: URL?
    let coverURL: URL?
    let location: String?
    let subtitle: String?
    let isDraft: Bool?
    let date: String?
    let createdOn: String?
    let lastPublished: String?
    let featured: Bool?
    var author: Author?

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case fieldData
        case isDraft
        case createdOn
        case lastPublished
    }
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    // Cache for createdDate to prevent repeated date parsing
    private var _createdDateCache: Date?
    var createdDate: Date? {
        mutating get {
            if let cached = _createdDateCache {
                return cached
            }
            guard let createdOn else { return nil }
            // Safely parse date with fallback
            if let date = Article.isoFormatter.date(from: createdOn) {
                _createdDateCache = date
                return date
            }
            // Try alternative date formats if ISO8601 fails
            let alternativeFormatters: [DateFormatter] = [
                DateFormatter().then { $0.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ" },
                DateFormatter().then { $0.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ" },
                DateFormatter().then { $0.dateFormat = "yyyy-MM-dd HH:mm:ss" }
            ]
            
            for formatter in alternativeFormatters {
                if let date = formatter.date(from: createdOn) {
                    _createdDateCache = date
                    return date
                }
            }
            return nil
        }
    }
    
    // Cache for publishedDate to prevent repeated date parsing
    private var _publishedDateCache: Date?
    var publishedDate: Date? {
        mutating get {
            if let cached = _publishedDateCache {
                return cached
            }
            guard let lastPublished else { return nil }
            // Safely parse date with fallback
            if let date = Article.isoFormatter.date(from: lastPublished) {
                _publishedDateCache = date
                return date
            }
            // Try alternative date formats if ISO8601 fails
            let alternativeFormatters: [DateFormatter] = [
                DateFormatter().then { $0.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ" },
                DateFormatter().then { $0.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ" },
                DateFormatter().then { $0.dateFormat = "yyyy-MM-dd HH:mm:ss" }
            ]
            
            for formatter in alternativeFormatters {
                if let date = formatter.date(from: lastPublished) {
                    _publishedDateCache = date
                    return date
                }
            }
            return nil
        }
    }
    
    enum FieldDataKeys: String, CodingKey {
        case name
        case slug
        case content
        case intro
        // Multiple possible slugs for the CMS field "Video / Trailer"
        case videoTrailer = "video-trailer"
        case video = "video"
        case trailerAlt = "trailer"
        case videoURL = "video-url"
        case videoLink = "video-link"
        case videoTrailerRaw = "Video / Trailer"
        case stjerne
        case topicID = "topic"
        case topicsIDs = "topics-multi-ref"
        case authorID = "author"
        case thumb
        case cover
        case location
        case subtitle
        case date
        case featured
    }

    enum ThumbKeys: String, CodingKey {
        case url
    }
    enum CoverKeys: String, CodingKey {
        case url
    }
    
    private static let trailerDecodingKeys: [FieldDataKeys] = [
        .videoTrailer,
        .video,
        .trailerAlt,
        .videoTrailerRaw,
        .videoURL,
        .videoLink
    ]
    
    private static func decodeTrailer(from container: KeyedDecodingContainer<FieldDataKeys>) -> String? {
        for key in trailerDecodingKeys {
            // Direct string
            if let rawValue = try? container.decode(String.self, forKey: key) {
                let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    return value
                }
            }
            
            // Structured payload with url / metadata
            if let payload = try? container.decode(VideoTrailerPayload.self, forKey: key) {
                if let html = payload.metadata?.html?.trimmingCharacters(in: .whitespacesAndNewlines), !html.isEmpty {
                    return html
                }
                if let url = payload.url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
                    return url
                }
            }
            
            // Fallback to generic dictionary payloads (e.g. Webflow richtext embeds)
            if let dictionaryPayload = try? container.decode([String: String].self, forKey: key) {
                if let html = dictionaryPayload["html"]?.trimmingCharacters(in: .whitespacesAndNewlines), !html.isEmpty {
                    return html
                }
                if let url = dictionaryPayload["url"]?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
                    return url
                }
            }
        }
        return nil
    }
    
    // Cache the thumbnailURL string to avoid repeated regex and string allocations
    private var _thumbnailURLCache: String?
    var thumbnailURL: String {
        mutating get {
            if let cached = _thumbnailURLCache {
                return cached
            }
            // Priority: thumbURL > coverURL > first image src in content > empty string
            
            if let thumbURL = thumbURL {
                _thumbnailURLCache = thumbURL.absoluteString
                return _thumbnailURLCache!
            }
            if let coverURL = coverURL {
                _thumbnailURLCache = coverURL.absoluteString
                return _thumbnailURLCache!
            }
            // Try to extract first image src from content HTML
            if let content = content, !content.isEmpty {
                // Using NSRegularExpression for performance and precise capture
                
                // Regex pattern to match <img ... src="..." or src='...'
                let pattern = "<img[^>]+src=[\"']([^\"']+)[\"']"
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let nsContent = content as NSString
                    let range = NSRange(location: 0, length: nsContent.length)
                    if let match = regex.firstMatch(in: content, options: [], range: range) {
                        if match.numberOfRanges >= 2 {
                            let srcRange = match.range(at: 1)
                            if srcRange.location != NSNotFound {
                                let src = nsContent.substring(with: srcRange)
                                // Safety check: ensure the extracted URL is valid
                                if !src.isEmpty && URL(string: src) != nil {
                                    _thumbnailURLCache = src
                                    return src
                                }
                            }
                        }
                    }
                }
            }
            _thumbnailURLCache = ""
            return ""
        }
    }
    
    // Computed property for topic name
    var topicName: String? {
        return topicID
    }
    
    // Computed property for author name
    var authorName: String? {
        return author?.name
    }
    
    // Custom hash implementation since we have a mutable author property
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(slug)
        hasher.combine(content)
        hasher.combine(trailer)
        hasher.combine(intro)
        hasher.combine(stjerne)
        hasher.combine(topicID)
        hasher.combine(topicsIDs)
        hasher.combine(authorID)
        hasher.combine(thumbURL)
        hasher.combine(coverURL)
        hasher.combine(location)
        hasher.combine(subtitle)
        hasher.combine(isDraft)
        hasher.combine(date)
        hasher.combine(createdOn)
        hasher.combine(lastPublished)
        hasher.combine(featured)
        hasher.combine(author?.id) // Only hash the author ID to avoid issues with mutable author
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(isDraft, forKey: .isDraft)
        try container.encodeIfPresent(createdOn, forKey: .createdOn)
        try container.encodeIfPresent(lastPublished, forKey: .lastPublished)
        
        var fieldData = container.nestedContainer(keyedBy: FieldDataKeys.self, forKey: .fieldData)
        try fieldData.encodeIfPresent(name, forKey: .name)
        try fieldData.encodeIfPresent(slug, forKey: .slug)
        try fieldData.encodeIfPresent(content, forKey: .content)
        // Prefer encoding to the canonical key "video-trailer"
        if let trailer = trailer, !trailer.isEmpty {
            try fieldData.encodeIfPresent(trailer, forKey: .videoTrailer)
        }
        try fieldData.encodeIfPresent(intro, forKey: .intro)
        try fieldData.encodeIfPresent(stjerne, forKey: .stjerne)
        try fieldData.encodeIfPresent(topicID, forKey: .topicID)
        try fieldData.encodeIfPresent(topicsIDs, forKey: .topicsIDs)
        try fieldData.encodeIfPresent(authorID, forKey: .authorID)
        try fieldData.encodeIfPresent(location, forKey: .location)
        try fieldData.encodeIfPresent(subtitle, forKey: .subtitle)
        try fieldData.encodeIfPresent(date, forKey: .date)
        try fieldData.encodeIfPresent(featured, forKey: .featured)
        // Encode thumbURL as nested container if present
        if let thumbURL = thumbURL {
            var thumbContainer = fieldData.nestedContainer(keyedBy: ThumbKeys.self, forKey: .thumb)
            try thumbContainer.encodeIfPresent(thumbURL, forKey: .url)
        }
        // Encode coverURL as nested container if present
        if let coverURL = coverURL {
            var coverContainer = fieldData.nestedContainer(keyedBy: CoverKeys.self, forKey: .cover)
            try coverContainer.encodeIfPresent(coverURL, forKey: .url)
        }
    }

    init(from decoder: Decoder) throws {
        // Top-level container keyed by CodingKeys
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // id is required
        id = try container.decode(String.self, forKey: .id)
        
        // Optional top-level properties
        isDraft = try container.decodeIfPresent(Bool.self, forKey: .isDraft)
        createdOn = try container.decodeIfPresent(String.self, forKey: .createdOn)
        lastPublished = try container.decodeIfPresent(String.self, forKey: .lastPublished)
        
        // fieldData nested container
        let fieldDataContainer = try container.nestedContainer(keyedBy: FieldDataKeys.self, forKey: .fieldData)
        
        name = try fieldDataContainer.decodeIfPresent(String.self, forKey: .name)
        slug = try fieldDataContainer.decodeIfPresent(String.self, forKey: .slug)
        content = try fieldDataContainer.decodeIfPresent(String.self, forKey: .content)
        intro = try fieldDataContainer.decodeIfPresent(String.self, forKey: .intro)
        stjerne = try fieldDataContainer.decodeIfPresent(Int.self, forKey: .stjerne)
        topicID = try fieldDataContainer.decodeIfPresent(String.self, forKey: .topicID)
        topicsIDs = try fieldDataContainer.decodeIfPresent([String].self, forKey: .topicsIDs)
        authorID = try fieldDataContainer.decodeIfPresent(String.self, forKey: .authorID)
        location = try fieldDataContainer.decodeIfPresent(String.self, forKey: .location)
        subtitle = try fieldDataContainer.decodeIfPresent(String.self, forKey: .subtitle)
        date = try fieldDataContainer.decodeIfPresent(String.self, forKey: .date)
        featured = try fieldDataContainer.decodeIfPresent(Bool.self, forKey: .featured)
        
        // Decode trailer from one of multiple possible keys, prefer videoTrailer, then trailerAlt, then videoTrailerRaw, videoURL, videoLink
        trailer = Article.decodeTrailer(from: fieldDataContainer)
        
        // Decode thumbURL from nested container
        if fieldDataContainer.contains(.thumb) {
            let thumbContainer = try fieldDataContainer.nestedContainer(keyedBy: ThumbKeys.self, forKey: .thumb)
            if let urlString = try thumbContainer.decodeIfPresent(String.self, forKey: .url) {
                thumbURL = URL(string: urlString)
            } else {
                thumbURL = nil
            }
        } else {
            thumbURL = nil
        }
        
        // Decode coverURL from nested container
        if fieldDataContainer.contains(.cover) {
            let coverContainer = try fieldDataContainer.nestedContainer(keyedBy: CoverKeys.self, forKey: .cover)
            if let urlString = try coverContainer.decodeIfPresent(String.self, forKey: .url) {
                coverURL = URL(string: urlString)
            } else {
                coverURL = nil
            }
        } else {
            coverURL = nil
        }
        
        // Initialize caches and mutable property
        _createdDateCache = nil
        _publishedDateCache = nil
        _thumbnailURLCache = nil
        author = nil
    }
    
    // Memberwise initializer for previews/tests
    init(
        id: String,
        name: String,
        slug: String,
        content: String,
        trailer: String? = nil,
        intro: String,
        stjerne: Int? = nil,
        topicID: String,
        topicsIDs: [String]? = nil,
        authorID: String? = nil,
        thumbURL: URL? = nil,
        coverURL: URL? = nil,
        location: String? = nil,
        subtitle: String? = nil,
        isDraft: Bool? = nil,
        date: String? = nil,
        createdOn: String? = nil,
        lastPublished: String? = nil,
        featured:Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.content = content
        self.trailer = trailer
        self.intro = intro
        self.stjerne = stjerne
        self.topicID = topicID
        self.topicsIDs = topicsIDs
        self.authorID = authorID
        self.thumbURL = thumbURL
        self.coverURL = coverURL
        self.location = location
        self.subtitle = subtitle
        self.isDraft = isDraft
        self.date = date
        self.createdOn = createdOn
        self.lastPublished = lastPublished
        self.featured = featured
        
        self._createdDateCache = nil
        self._publishedDateCache = nil
        self._thumbnailURLCache = nil
        self.author = nil
    }
    
    // Computed property til at returnere stjerne rating
    var rating: Int {
        return stjerne ?? 0
    }
    
    // Note: Structs do not have deinit. For debug: no deinit print possible here.
}

//#if DEBUG
extension Article {
    static var sample: Article {
        var article = Article(
            id: "sample-1",
            name: "Eksempelartikel: Fremtidens Design",
            slug: "eksempel-fremtidens-design",
            content: "Dette er en eksempel artikel med rigtig indhold. Her kan du læse om de nyeste trends inden for design og teknologi. Artiklen indeholder flere afsnit med interessant information om, hvordan design former vores verden og påvirker vores dagligdag.\n\nVi udforsker forskellige aspekter af moderne design og ser på, hvordan det påvirker både brugere og udviklere. Fra minimalistiske tilgang til komplekse systemer, deres påvirkning på brugeroplevelsen og fremtidens muligheder.",
            trailer: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            intro: "Dette er en introduktion til en spændende artikel om, hvordan design former vores verden.",
            stjerne: 5,
            topicID: "Design",
            topicsIDs: ["Innovation", "Teknologi"],
            authorID: "AI Skribent",
            thumbURL: URL(string: "https://images.unsplash.com/photo-1518770660439-4636190af475?q=80&w=2070"),
            coverURL: URL(string: "https://images.unsplash.com/photo-1518770660439-4636190af475?q=80&w=2070"),
            location: "Aarhus",
            subtitle: "Sådan former design vores verden",
            isDraft: false,
            date: "2024-04-01",
            createdOn: "2024-04-01T10:00:00.000Z",
            lastPublished: "2024-04-01T10:00:00.000Z",
            featured: true
        )
        article.author = Author(
            id: "author-1",
            name: "Frederik Kragh",
            bio: "Freelance journalist og tech-entusiast",
            imageURL: "https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?q=80&w=2070",
            position: "Chefredaktør",
            photoURL: "https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?q=80&w=2070"
        )
        return article
    }
}
//#endif
