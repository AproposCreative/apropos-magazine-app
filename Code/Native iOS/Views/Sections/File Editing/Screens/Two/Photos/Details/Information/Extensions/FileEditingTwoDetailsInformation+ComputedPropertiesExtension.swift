//
//  FileEditingTwoDetailsInformation+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension FileEditingTwoDetailsInformationView {
    
    // MARK: - Computed Properties:
    
    /// Title of the photo:
    var title: String {
        photo.title
    }
    
    /// Size of the photo:
    var size: String {
        photo.size.formatted(.byteCount(style: .file))
    }
    
    /// Date when the photo was last updated:
    var lastUpdated: String {
        photo.lastUpdated.formatted(.dateTime.year().month().day())
    }
    
    /// Name of the person who has created the photo:
    var createdBy: String {
        photo.createdBy
    }
    
    /// Style of the view:
    var style: NT_LabelStyle {
        .titleOnly
    }
}
