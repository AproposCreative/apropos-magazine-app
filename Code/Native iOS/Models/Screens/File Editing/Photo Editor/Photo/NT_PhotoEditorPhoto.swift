//
//  NT_PhotoEditorPhoto.swift
//  Native
//

import Foundation

struct NT_PhotoEditorPhoto {
    
    // MARK: - Properties:
    
    /// Identifier of the photo:
    let id: String
    
    /// An actual image of the photo:
    let image: String
    
    /// An actual full image of the photo:
    let fullImage: String
    
    /// Title of the photo:
    let title: String
    
    /// Size of the photo:
    let size: Measurement<UnitInformationStorage>
    
    /// Date when the photo was last updated:
    let lastUpdated: Date
    
    /// Name of the person who has created the photo:
    let createdBy: String
    
    /// Identifier of the section that the photo is a part of:
    let section: String
    
    init(
        id: String,
        image: String,
        fullImage: String,
        title: String,
        size: Measurement<UnitInformationStorage>,
        lastUpdated: Date,
        createdBy: String,
        section: String
    ) {
        
        /// Properties initialization:
        self.id = id
        self.image = image
        self.fullImage = fullImage
        self.title = title
        self.size = size
        self.lastUpdated = lastUpdated
        self.createdBy = createdBy
        self.section = section
    }
    
    // MARK: - Computed properties:
    
    /// Time interval since the photo was last updated as a string:
    var timeIntervalSinceLastUpdated: String {
        if let timeInterval: String = Formatters.timeInterval(fromDate: lastUpdated) {
            return "Updated \(timeInterval) ago"
        } else {
            return ""
        }
    }
}

// MARK: - Identifiable:

extension NT_PhotoEditorPhoto: Identifiable {  }

// MARK: - Equatable:

extension NT_PhotoEditorPhoto: Equatable {  }

// MARK: - Hashable:

extension NT_PhotoEditorPhoto: Hashable {  }

// MARK: - Encodable:

extension NT_PhotoEditorPhoto: Encodable {
    
    // MARK: - Functions:
    
    /// Encodes the values of the photo using the given encoder:
    func encode(to encoder: Encoder) throws {
        
        /// Firstly getting the container to encode with:
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        /// Then encoding the values:
        try container.encode(id, forKey: .id)
        try container.encode(image, forKey: .image)
        try container.encode(fullImage, forKey: .fullImage)
        try container.encode(title, forKey: .title)
        try container.encode(size, forKey: .size)
        try container.encode(lastUpdated, forKey: .lastUpdated)
        try container.encode(createdBy, forKey: .createdBy)
        try container.encode(section, forKey: .section)
    }
}

// MARK: - Decodable:

extension NT_PhotoEditorPhoto: Decodable {
    
    // MARK: - Initializer:
    
    init(from decoder: Decoder) throws {
        
        /// Firstly getting the container to decode with:
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        /// Then decoding the values and initializing the properties:
        id = try container.decode(String.self, forKey: .id)
        image = (try? container.decode(String.self, forKey: .image)) ?? ""
        fullImage = (try? container.decode(String.self, forKey: .fullImage)) ?? ""
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        size = (try? container.decode(Measurement<UnitInformationStorage>.self, forKey: .size)) ?? .init(value: 0, unit: .bytes)
        lastUpdated = (try? container.decode(Date.self, forKey: .lastUpdated)) ?? .now
        createdBy = (try? container.decode(String.self, forKey: .createdBy)) ?? ""
        section = (try? container.decode(String.self, forKey: .section)) ?? ""
    }
}

// MARK: - Coding keys:

extension NT_PhotoEditorPhoto {
    
    // MARK: - Enums:
    
    enum CodingKeys: CodingKey {
        case id
        case image
        case fullImage
        case title
        case size
        case lastUpdated
        case createdBy
        case section
    }
}

// MARK: - Example:

extension NT_PhotoEditorPhoto {
    
    // MARK: - Computed properties:
    
    /// An array of the example photos:
    static var example: [NT_PhotoEditorPhoto] {
        [
            .init(
                id: "Item.1",
                image: Images.fileEditing21,
                fullImage: Images.fileEditing5,
                title: "Bright Sun",
                size: .init(
                    value: 9.6,
                    unit: .megabytes
                ),
                lastUpdated: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 6
                ),
                createdBy: "John Smith",
                section: "Item.1"
            ),
            .init(
                id: "Item.2",
                image: Images.fileEditing22,
                fullImage: Images.fileEditing5,
                title: "Ocean Sunset",
                size: .init(
                    value: 9.6,
                    unit: .megabytes
                ),
                lastUpdated: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 1
                ),
                createdBy: "John Smith",
                section: "Item.1"
            ),
            .init(
                id: "Item.3",
                image: Images.fileEditing23,
                fullImage: Images.fileEditing5,
                title: "Mountains",
                size: .init(
                    value: 9.6,
                    unit: .megabytes
                ),
                lastUpdated: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 7,
                    withDay: 25
                ),
                createdBy: "John Smith",
                section: "Item.2"
            ),
            .init(
                id: "Item.4",
                image: Images.fileEditing24,
                fullImage: Images.fileEditing5,
                title: "Wonderful View",
                size: .init(
                    value: 9.6,
                    unit: .megabytes
                ),
                lastUpdated: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 7,
                    withDay: 10
                ),
                createdBy: "John Smith",
                section: "Item.2"
            ),
            .init(
                id: "Item.5",
                image: Images.fileEditing25,
                fullImage: Images.fileEditing5,
                title: "Sky with Colors",
                size: .init(
                    value: 9.6,
                    unit: .megabytes
                ),
                lastUpdated: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 6,
                    withDay: 15
                ),
                createdBy: "John Smith",
                section: "Item.2"
            ),
            .init(
                id: "Item.6",
                image: Images.fileEditing26,
                fullImage: Images.fileEditing5,
                title: "Golden Hour",
                size: .init(
                    value: 9.6,
                    unit: .megabytes
                ),
                lastUpdated: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 5,
                    withDay: 1
                ),
                createdBy: "John Smith",
                section: "Item.2"
            ),
            .init(
                id: "Item.7",
                image: Images.fileEditing27,
                fullImage: Images.fileEditing5,
                title: "Lake View",
                size: .init(
                    value: 9.6,
                    unit: .megabytes
                ),
                lastUpdated: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 4,
                    withDay: 20
                ),
                createdBy: "John Smith",
                section: "Item.2"
            ),
            .init(
                id: "Item.8",
                image: Images.fileEditing28,
                fullImage: Images.fileEditing5,
                title: "Beach Sunset",
                size: .init(
                    value: 9.6,
                    unit: .megabytes
                ),
                lastUpdated: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 4,
                    withDay: 10
                ),
                createdBy: "John Smith",
                section: "Item.2"
            )
        ]
    }
}
