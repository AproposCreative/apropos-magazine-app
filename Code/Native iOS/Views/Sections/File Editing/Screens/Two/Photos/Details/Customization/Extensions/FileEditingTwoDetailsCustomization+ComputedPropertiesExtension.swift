//
//  FileEditingTwoDetailsCustomization+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension FileEditingTwoDetailsCustomizationView {
    
    // MARK: - Computed properties:
    
    /// An array of the resolutions of the image to select from:
    var resolutions: [NT_ImageResolution] {
        NT_ImageResolution.allCases
    }
    
    /// An array of the aspect ratios of the image to select from:
    var aspectRatios: [NT_ImageAspectRatio] {
        NT_ImageAspectRatio.allCases
    }
    
    /// An array of the grids of the image to select from:
    var grids: [NT_ImageGrid] {
        NT_ImageGrid.allCases.filter { $0 != .none }
    }
    
    /// Range of the saturation and the brightness pickers:
    var saturationBrightnessRange: ClosedRange<Double> {
        0...1
    }
    
    /// Font of the view:
    var font: Font {
        .headline
    }
}
