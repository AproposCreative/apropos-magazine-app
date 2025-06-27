//
//  NT_IconBackgroundSize.swift
//  Native
//

import SwiftUI

enum NT_IconSize {
    
    // MARK: - Cases:
    
    case sixteenPixels
    case twentyFourPixels
    case thirtyTwoPixels
    case fortyEightPixels
    case fiftySixPixels
    case sixtyFourPixels
    case ninetySixPixels
    case twoHundredPixels
    case custom (
        font: Font,
        nonBackgroundFont: Font,
        frame: CGFloat?,
        cornerRadius: Double,
        cornerStyle: RoundedCornerStyle
    )
    
    // MARK: - Computed properties:
    
    /// Font of the icon:
    var font: Font {
        switch self {
        case .sixteenPixels:
            return .system(
                size: 9,
                weight: .semibold,
                design: .default
            )
        case .twentyFourPixels:
            return .system(
                size: 12,
                weight: .semibold,
                design: .default
            )
        case .thirtyTwoPixels:
            return .system(
                size: 15,
                weight: .semibold,
                design: .default
            )
        case .fortyEightPixels:
            return .system(
                size: 22,
                weight: .semibold,
                design: .default
            )
        case .fiftySixPixels:
            return .system(
                size: 28,
                weight: .semibold,
                design: .default
            )
        case .sixtyFourPixels:
            return .system(
                size: 30,
                weight: .semibold,
                design: .default
            )
        case .ninetySixPixels:
            return .system(
                size: 48,
                weight: .semibold,
                design: .default
            )
        case .twoHundredPixels:
            return .system(
                size: 96,
                weight: .semibold,
                design: .default
            )
        case .custom(let font, _, _, _, _):
            return font
        }
    }
    
    /// Font of the icon without the background:
    var nonBackgroundFont: Font {
        switch self {
        case .sixteenPixels:
            return .system(
                size: 11,
                weight: .semibold,
                design: .default
            )
        case .twentyFourPixels:
            return .system(
                size: 17,
                weight: .semibold,
                design: .default
            )
        case .thirtyTwoPixels:
            return .system(
                size: 22,
                weight: .semibold,
                design: .default
            )
        case .fortyEightPixels:
            return .system(
                size: 34,
                weight: .semibold,
                design: .default
            )
        case .fiftySixPixels:
            return .system(
                size: 40,
                weight: .semibold,
                design: .default
            )
        case .sixtyFourPixels:
            return .system(
                size: 48,
                weight: .semibold,
                design: .default
            )
        case .ninetySixPixels:
            return .system(
                size: 64,
                weight: .semibold,
                design: .default
            )
        case .twoHundredPixels:
            return .system(
                size: 136,
                weight: .semibold,
                design: .default
            )
        case .custom(_, let nonBackgroundFont, _, _, _):
            return nonBackgroundFont
        }
    }
    
    /// Frame of the icon:
    var frame: CGFloat? {
        switch self {
        case .sixteenPixels: return 16
        case .twentyFourPixels: return 24
        case .thirtyTwoPixels: return 32
        case .fortyEightPixels: return 48
        case .fiftySixPixels: return 56
        case .sixtyFourPixels: return 64
        case .ninetySixPixels: return 96
        case .twoHundredPixels: return 200
        case .custom(_, _, let frame, _, _): return frame
        }
    }
    
    /// Radius of the rounded corners of the icon:
    var cornerRadius: Double {
        switch self {
        case .sixteenPixels: return 4
        case .twentyFourPixels: return 6
        case .thirtyTwoPixels: return 8
        case .fortyEightPixels: return 12
        case .fiftySixPixels: return 14
        case .sixtyFourPixels: return 16
        case .ninetySixPixels: return 24
        case .twoHundredPixels: return 48
        case .custom(_, _, _, let cornerRadius, _): return cornerRadius
        }
    }
    
    /// Style of the rounded corners of the icon:
    var cornerStyle: RoundedCornerStyle {
        switch self {
        case .sixteenPixels,
                .twentyFourPixels,
                .thirtyTwoPixels,
                .fortyEightPixels,
                .fiftySixPixels,
                .sixtyFourPixels,
                .ninetySixPixels,
                .twoHundredPixels:
            return .continuous
        case .custom(_, _, _, _, let cornerStyle):
            return cornerStyle
        }
    }
}

// MARK: - Equatable:

extension NT_IconSize: Equatable {  }

// MARK: - Hashable:

extension NT_IconSize: Hashable {  }
