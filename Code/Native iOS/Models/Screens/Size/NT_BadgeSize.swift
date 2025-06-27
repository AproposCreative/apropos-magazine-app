//
//  NT_BadgeSize.swift
//  Native
//

import SwiftUI

enum NT_BadgeSize {
    
    // MARK: - Cases:
    
    case extraSmall
    case small
    case large
    case custom (
        iconFont: Font,
        iconFrame: CGFloat?,
        titleFont: Font,
        spacing: Double,
        verticalPadding: Double,
        horizontalPadding: Double,
        borderWidth: Double,
        cornerRadius: Double,
        cornerStyle: RoundedCornerStyle
    )
    
    // MARK: - Computed properties:
    
    /// Font of the icon of the badge:
    var iconFont: Font {
        switch self {
        case .extraSmall:
            return .system(
                size: 13,
                weight: .regular,
                design: .default
            )
        case .small:
            return .system(
                size: 13,
                weight: .regular,
                design: .default
            )
        case .large:
            return .system(
                size: 17,
                weight: .regular,
                design: .default
            )
        case .custom(let iconFont, _, _, _, _, _, _, _, _):
            return iconFont
        }
    }
    
    /// Size of the frame of the icon of the badge:
    var iconFrame: CGFloat? {
        switch self {
        case .extraSmall: return 16
        case .small: return 16
        case .large: return 24
        case .custom(_, let iconFrame, _, _, _, _, _, _, _): return iconFrame
        }
    }
    
    /// Font of the title of the badge:
    var titleFont: Font {
        switch self {
        case .extraSmall: return .footnote.bold()
        case .small: return .footnote.weight(.heavy)
        case .large: return .headline.weight(.heavy)
        case .custom(_, _, let titleFont, _, _, _, _, _, _): return titleFont
        }
    }
    
    /// Spacing between the content of the badge:
    var spacing: Double {
        switch self {
        case .extraSmall: return 4
        case .small: return 6
        case .large: return 6
        case .custom(_, _, _, let spacing, _, _, _, _, _): return spacing
        }
    }
    
    /// Vertical padding of the badge:
    var verticalPadding: Double {
        switch self {
        case .extraSmall: return 4
        case .small: return 4
        case .large: return 8
        case .custom(_, _, _, _, let verticalPadding, _, _, _, _): return verticalPadding
        }
    }
    
    /// Horizontal padding of the badge:
    var horizontalPadding: Double {
        switch self {
        case .extraSmall: return 8
        case .small: return 8
        case .large: return 12
        case .custom(_, _, _, _, _, let horizontalPadding, _, _, _): return horizontalPadding
        }
    }
    
    /// Width of the border of the badge:
    var borderWidth: Double {
        switch self {
        case .extraSmall: return 0
        case .small: return 2
        case .large: return 3
        case .custom(_, _, _, _, _, _, let borderWidth, _, _): return borderWidth
        }
    }
    
    /// Radius of the rounded corners of the badge:
    var cornerRadius: Double {
        switch self {
        case .extraSmall: return 8
        case .small: return 8
        case .large: return 14
        case .custom(_, _, _, _, _, _, _, let cornerRadius, _): return cornerRadius
        }
    }
    
    /// Style of the rounded corners of the badge:
    var cornerStyle: RoundedCornerStyle {
        switch self {
        case .extraSmall,
                .small,
                .large:
            return .continuous
        case .custom(_, _, _, _, _, _, _, _, let cornerStyle):
            return cornerStyle
        }
    }
}

// MARK: - Equatable:

extension NT_BadgeSize: Equatable {  }

// MARK: - Hashable:

extension NT_BadgeSize: Hashable {  }
