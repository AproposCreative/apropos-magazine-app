import Foundation

struct WhatsNewItem: Identifiable, Codable {
    let icon: String
    let title: String
    let description: String

    var id: String {
        "\(title)-\(description)"
    }
}

struct WhatsNewEntry: Identifiable, Codable {
    let version: String
    let title: String
    let subtitle: String?
    let items: [WhatsNewItem]
    let ctaTitle: String?
    let ctaURL: URL?

    var id: String { version }

    private enum CodingKeys: String, CodingKey {
        case version, title, subtitle, items
        case ctaTitle
        case ctaURL
    }

    init(version: String,
         title: String,
         subtitle: String? = nil,
         items: [WhatsNewItem],
         ctaTitle: String? = nil,
         ctaURL: URL? = nil) {
        self.version = version
        self.title = title
        self.subtitle = subtitle
        self.items = items
        self.ctaTitle = ctaTitle
        self.ctaURL = ctaURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        items = try container.decode([WhatsNewItem].self, forKey: .items)
        ctaTitle = try container.decodeIfPresent(String.self, forKey: .ctaTitle)

        if let urlString = try container.decodeIfPresent(String.self, forKey: .ctaURL),
           let url = URL(string: urlString) {
            ctaURL = url
        } else {
            ctaURL = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(subtitle, forKey: .subtitle)
        try container.encode(items, forKey: .items)
        try container.encodeIfPresent(ctaTitle, forKey: .ctaTitle)
        try container.encodeIfPresent(ctaURL?.absoluteString, forKey: .ctaURL)
    }
}
