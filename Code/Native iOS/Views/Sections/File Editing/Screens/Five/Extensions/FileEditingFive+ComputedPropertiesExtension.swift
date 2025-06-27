//
//  FileEditingFive+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension FileEditingFiveView {
    
    // MARK: - Computed properties:
    
    /// Title of the photo to edit:
    var title: String {
        photo.title
    }
    
    /// An actual image of the photo to edit:
    var image: Image {
        .init(photo.fullImage)
    }
    
    /// Font of the buttons that are displayed on the view:
    var buttonFont: Font {
        .body
    }
    
    /// Symbol variant of the icons of the buttons that are displayed on the view:
    var buttonIconSymbolVariant: SymbolVariants {
        .none
    }
    
    /// Style of the buttons that are displayed on the view:
    var buttonStyle: NT_LabelStyle {
        .iconOnly
    }
}
