//
//  NT_DesignToolFile.swift
//  Native
//

import Foundation

struct NT_DesignToolFile {
    
    // MARK: - Properties:
    
    /// Identifier of the file:
    let id: String
    
    /// Title of the file:
    let title: String
    
    /// Date when the file was last saved:
    let lastSaved: Date
    
    /// Thumbnail of the file:
    let thumbnail: String
    
    /// An array of the layers of the file:
    let layers: [NT_DesignToolLayer]
    
    /// Identifier of the folder that the file is part of:
    let folder: String
    
    /// An array of the identifiers of the tags that the file is part of:
    let tags: [String]
    
    init(
        id: String,
        title: String,
        lastSaved: Date,
        thumbnail: String,
        layers: [NT_DesignToolLayer],
        folder: String,
        tags: [String]
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.lastSaved = lastSaved
        self.thumbnail = thumbnail
        self.layers = layers
        self.folder = folder
        self.tags = tags
    }
    
    // MARK: - Computed properties:
    
    /// Time interval since the file was last saved as a string:
    var timeIntervalSinceLastSaved: String {
        if let timeInterval: String = Formatters.timeInterval(fromDate: lastSaved) {
            return timeInterval
        } else {
            return ""
        }
    }
}

// MARK: - Identifiable:

extension NT_DesignToolFile: Identifiable {  }

// MARK: - Equatable:

extension NT_DesignToolFile: Equatable {  }

// MARK: - Hashable:

extension NT_DesignToolFile: Hashable {  }

// MARK: - Codable:

extension NT_DesignToolFile: Codable {  }

// MARK: - Example:

extension NT_DesignToolFile {
    
    // MARK: - Computed properties:
    
    /// An array of the example files:
    static var example: [NT_DesignToolFile] {
        [
            .init(
                id: "Item.1",
                title: "Web App Design",
                lastSaved: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 6,
                    withHour: 11,
                    withMinute: 45
                ),
                thumbnail: Images.fileEditing11,
                layers: NT_DesignToolLayer.example,
                folder: "Item.1",
                tags: [
                    "Item.1",
                    "Item.2",
                    "Item.6",
                    "Item.10"
                ]
            ),
            .init(
                id: "Item.2",
                title: "Multipurpose Design System",
                lastSaved: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 1,
                    withHour: 12,
                    withMinute: 15
                ),
                thumbnail: Images.fileEditing12,
                layers: NT_DesignToolLayer.example,
                folder: "Item.1",
                tags: [
                    "Item.6",
                    "Item.8",
                    "Item.9",
                    "Item.10"
                ]
            ),
            .init(
                id: "Item.3",
                title: "UI Components Library",
                lastSaved: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 7,
                    withDay: 15,
                    withHour: 14,
                    withMinute: 30
                ),
                thumbnail: Images.fileEditing13,
                layers: NT_DesignToolLayer.example,
                folder: "Item.1",
                tags: [
                    "Item.1",
                    "Item.2",
                    "Item.4",
                    "Item.6",
                    "Item.10"
                ]
            ),
            .init(
                id: "Item.4",
                title: "Styleguide Template",
                lastSaved: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 5,
                    withDay: 31,
                    withHour: 8,
                    withMinute: 0
                ),
                thumbnail: Images.fileEditing14,
                layers: NT_DesignToolLayer.example,
                folder: "Item.1",
                tags: [
                    "Item.1",
                    "Item.6",
                    "Item.8",
                    "Item.9",
                    "Item.10"
                ]
            ),
            .init(
                id: "Item.5",
                title: "Native Components",
                lastSaved: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 2,
                    withDay: 20,
                    withHour: 11,
                    withMinute: 30
                ),
                thumbnail: Images.fileEditing15,
                layers: NT_DesignToolLayer.example,
                folder: "Item.2",
                tags: [
                    "Item.2",
                    "Item.3",
                    "Item.6"
                ]
            ),
            .init(
                id: "Item.6",
                title: "Onboarding Screens",
                lastSaved: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 1,
                    withDay: 19,
                    withHour: 18,
                    withMinute: 45
                ),
                thumbnail: Images.fileEditing16,
                layers: NT_DesignToolLayer.example,
                folder: "Item.2",
                tags: [
                    "Item.4",
                    "Item.6",
                    "Item.7",
                    "Item.8",
                    "Item.9",
                    "Item.10"
                ]
            ),
            .init(
                id: "Item.7",
                title: "Home Screen Design",
                lastSaved: .dateWithComponents(
                    withYear: 2023,
                    withMonth: 6,
                    withDay: 25,
                    withHour: 18,
                    withMinute: 30
                ),
                thumbnail: Images.fileEditing17,
                layers: NT_DesignToolLayer.example,
                folder: "Item.2",
                tags: [
                    "Item.2",
                    "Item.3",
                    "Item.4",
                    "Item.6",
                    "Item.10"
                ]
            ),
            .init(
                id: "Item.8",
                title: "Developer Handoff",
                lastSaved: .dateWithComponents(
                    withYear: 2023,
                    withMonth: 4,
                    withDay: 30,
                    withHour: 19,
                    withMinute: 45
                ),
                thumbnail: Images.fileEditing18,
                layers: NT_DesignToolLayer.example,
                folder: "Item.2",
                tags: [
                    "Item.6",
                    "Item.7",
                    "Item.8",
                    "Item.9",
                    "Item.10"
                ]
            ),
            .init(
                id: "Item.9",
                title: "User Research Templates",
                lastSaved: .dateWithComponents(
                    withYear: 2023,
                    withMonth: 2,
                    withDay: 3,
                    withHour: 10,
                    withMinute: 25
                ),
                thumbnail: Images.fileEditing19,
                layers: NT_DesignToolLayer.example,
                folder: "Item.2",
                tags: [
                    "Item.2",
                    "Item.3",
                    "Item.4",
                    "Item.6"
                ]
            ),
            .init(
                id: "Item.10",
                title: "[Obsolete] Initial Sketches",
                lastSaved: .dateWithComponents(
                    withYear: 2022,
                    withMonth: 8,
                    withDay: 31,
                    withHour: 8,
                    withMinute: 30
                ),
                thumbnail: Images.fileEditing110,
                layers: NT_DesignToolLayer.example,
                folder: "Item.2",
                tags: [
                    "Item.2",
                    "Item.5",
                    "Item.7",
                    "Item.8",
                    "Item.10"
                ]
            )
        ]
    }
}
