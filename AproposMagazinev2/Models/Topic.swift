import Foundation

struct Topic: Identifiable, Decodable, Equatable {
    let id: String
    let name: String
    let description: String?
    let icon: String?
    let color: String?
    let isActive: Bool
    let sortOrder: Int?
    let articleCount: Int?
    
    // Cached lowercase name for performance optimization to avoid repeated lowercasing
    // Useful when topic lists are large and these computed properties are accessed frequently
    private let lowercasedName: String
    
    // Webflow API decoding
    private enum CodingKeys: String, CodingKey {
        case id
        case fieldData
    }
    private enum FieldDataKeys: String, CodingKey {
        case name
        case description
        case icon
        case color
        case isActive = "is-active"
        case sortOrder = "sort-order"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let fieldData = try container.nestedContainer(keyedBy: FieldDataKeys.self, forKey: .fieldData)
        name = try fieldData.decode(String.self, forKey: .name)
        description = try fieldData.decodeIfPresent(String.self, forKey: .description)
        icon = try fieldData.decodeIfPresent(String.self, forKey: .icon)
        color = try fieldData.decodeIfPresent(String.self, forKey: .color)
        isActive = try fieldData.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        sortOrder = try fieldData.decodeIfPresent(Int.self, forKey: .sortOrder)
        articleCount = nil // Will be calculated dynamically
        
        lowercasedName = name.lowercased()
    }
    
    // For previews
    init(id: String, name: String, description: String? = nil, icon: String? = nil, color: String? = nil, isActive: Bool = true, sortOrder: Int? = nil, articleCount: Int? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.color = color
        self.isActive = isActive
        self.sortOrder = sortOrder
        self.articleCount = articleCount
        
        lowercasedName = name.lowercased()
    }
    
    // Computed properties for better UX
    var displayIcon: String {
        icon ?? defaultIcon
    }
    
    var displayColor: String {
        color ?? defaultColor
    }
    
    private var defaultIcon: String {
        switch lowercasedName {
        case let name where name.contains("design"): return "paintpalette.fill"
        case let name where name.contains("musik"): return "music.note.list"
        case let name where name.contains("litteratur"): return "book.fill"
        case let name where name.contains("nyhed"): return "newspaper.fill"
        case let name where name.contains("mad"): return "fork.knife"
        case let name where name.contains("rejse"): return "airplane"
        case let name where name.contains("kunst"): return "paintbrush.pointed.fill"
        case let name where name.contains("teknologi"): return "cpu.fill"
        default: return "square.grid.2x2.fill"
        }
    }
    
    private var defaultColor: String {
        switch lowercasedName {
        case let name where name.contains("design"): return "purple"
        case let name where name.contains("musik"): return "blue"
        case let name where name.contains("litteratur"): return "orange"
        case let name where name.contains("nyhed"): return "teal"
        case let name where name.contains("mad"): return "red"
        case let name where name.contains("rejse"): return "mint"
        case let name where name.contains("kunst"): return "pink"
        case let name where name.contains("teknologi"): return "indigo"
        default: return "accent"
        }
    }
}

// MARK: - WebflowSection Model for Webflow Sections Collection
struct WebflowSection: Identifiable, Decodable, Equatable {
    let id: String
    let name: String
    let description: String?
    let icon: String?
    let color: String?
    let isActive: Bool
    let sortOrder: Int?
    let articleCount: Int?
    
    // Cached lowercase name for performance optimization to avoid repeated lowercasing
    // Useful when section lists are large and these computed properties are accessed frequently
    private let lowercasedName: String
    
    // Webflow API decoding
    private enum CodingKeys: String, CodingKey {
        case id
        case fieldData
    }
    private enum FieldDataKeys: String, CodingKey {
        case name
        case description
        case icon
        case color
        case isActive = "is-active"
        case sortOrder = "sort-order"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let fieldData = try container.nestedContainer(keyedBy: FieldDataKeys.self, forKey: .fieldData)
        name = try fieldData.decode(String.self, forKey: .name)
        description = try fieldData.decodeIfPresent(String.self, forKey: .description)
        icon = try fieldData.decodeIfPresent(String.self, forKey: .icon)
        color = try fieldData.decodeIfPresent(String.self, forKey: .color)
        isActive = try fieldData.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        sortOrder = try fieldData.decodeIfPresent(Int.self, forKey: .sortOrder)
        articleCount = nil // Will be calculated dynamically
        
        lowercasedName = name.lowercased()
    }
    
    // For previews
    init(id: String, name: String, description: String? = nil, icon: String? = nil, color: String? = nil, isActive: Bool = true, sortOrder: Int? = nil, articleCount: Int? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.color = color
        self.isActive = isActive
        self.sortOrder = sortOrder
        self.articleCount = articleCount
        
        lowercasedName = name.lowercased()
    }
    
    // Computed properties for better UX
    var displayIcon: String {
        icon ?? defaultIcon
    }
    
    var displayColor: String {
        color ?? defaultColor
    }
    
    private var defaultIcon: String {
        switch lowercasedName {
        case let name where name.contains("serier"): return "tv.fill"
        case let name where name.contains("film"): return "film.fill"
        case let name where name.contains("musik"): return "music.note.list"
        case let name where name.contains("kultur"): return "paintbrush.pointed.fill"
        case let name where name.contains("bøger"): return "book.fill"
        case let name where name.contains("anmeldelser"): return "star.fill"
        case let name where name.contains("koncerter"): return "music.mic"
        default: return "square.grid.2x2.fill"
        }
    }
    
    private var defaultColor: String {
        switch lowercasedName {
        case let name where name.contains("serier"): return "blue"
        case let name where name.contains("film"): return "purple"
        case let name where name.contains("musik"): return "green"
        case let name where name.contains("kultur"): return "orange"
        case let name where name.contains("bøger"): return "brown"
        case let name where name.contains("anmeldelser"): return "yellow"
        case let name where name.contains("koncerter"): return "pink"
        default: return "accent"
        }
    }
}
