//
//  NT_Badge.swift
//  Native
//

import SwiftUI

struct NT_Badge {
    
    // MARK: - Properties:
    
    /// Identifier of the badge:
    let id: String
    
    /// 'Bool' value indicating whether or not the icon of the badge should be shown at all:
    let isShowingIcon: Bool
    
    /// An actual icon of the badge to display if applicable:
    let icon: String
    
    /// Symbol variant of the icon of the badge if applicable (It could be '.fill', '.circle', etc.):
    let iconSymbolVariant: SymbolVariants
    
    /// Color of the icon of the badge if applicable:
    let iconColor: Color
    
    /// Starting color of the gradient of the icon of the badge if applicable:
    let iconGradientStart: Color
    
    /// Ending color of the gradient of the icon of the badge if applicable:
    let iconGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the icon of the badge should have a gradient applied to it if applicable:
    let isIconColorGradient: Bool
    
    /// Title of the badge to display:
    let title: String
    
    /// 'Bool' value indicating whether or not the title of the badge should be localized:
    let isTitleLocalized: Bool
    
    /// Text case of the title of the badge:
    let titleTextCase: Text.Case?
    
    /// Alignment of the title of the badge:
    let titleAlignment: TextAlignment
    
    /// Color of the title of the badge:
    let titleColor: Color
    
    /// Starting color of the gradient of the title of the badge if applicable:
    let titleGradientStart: Color
    
    /// Ending color of the gradient of the title of the badge if applicable:
    let titleGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the title of the badge should have a gradient applied to it:
    let isTitleColorGradient: Bool
    
    /// Color of the background of the badge:
    let backgroundColor: Color
    
    /// Starting color of the gradient of the background of the badge:
    let backgroundGradientStart: Color
    
    /// Ending color of the gradient of the background of the badge:
    let backgroundGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the background of the badge should have a gradient applied to it:
    let isBackgroundColorGradient: Bool
    
    /// 'Bool' value indicating whether or not the border of the badge should be shown at all:
    let isShowingBorder: Bool
    
    /// Color of the border of the badge:
    let borderColor: Color
    
    /// Size of the badge:
    let size: NT_BadgeSize
    
    init(
        id: String,
        isShowingIcon: Bool,
        icon: String,
        iconSymbolVariant: SymbolVariants,
        iconColor: Color,
        iconGradientStart: Color,
        iconGradientEnd: Color,
        isIconColorGradient: Bool,
        title: String,
        isTitleLocalized: Bool,
        titleTextCase: Text.Case?,
        titleAlignment: TextAlignment,
        titleColor: Color,
        titleGradientStart: Color,
        titleGradientEnd: Color,
        isTitleColorGradient: Bool,
        backgroundColor: Color,
        backgroundGradientStart: Color,
        backgroundGradientEnd: Color,
        isBackgroundColorGradient: Bool,
        isShowingBorder: Bool,
        borderColor: Color,
        size: NT_BadgeSize
    ) {
        
        /// Properties initialization:
        self.id = id
        self.isShowingIcon = isShowingIcon
        self.icon = icon
        self.iconSymbolVariant = iconSymbolVariant
        self.iconColor = iconColor
        self.iconGradientStart = iconGradientStart
        self.iconGradientEnd = iconGradientEnd
        self.isIconColorGradient = isIconColorGradient
        self.title = title
        self.isTitleLocalized = isTitleLocalized
        self.titleTextCase = titleTextCase
        self.titleAlignment = titleAlignment
        self.titleColor = titleColor
        self.titleGradientStart = titleGradientStart
        self.titleGradientEnd = titleGradientEnd
        self.isTitleColorGradient = isTitleColorGradient
        self.backgroundColor = backgroundColor
        self.backgroundGradientStart = backgroundGradientStart
        self.backgroundGradientEnd = backgroundGradientEnd
        self.isBackgroundColorGradient = isBackgroundColorGradient
        self.isShowingBorder = isShowingBorder
        self.borderColor = borderColor
        self.size = size
    }
}

// MARK: - Identifiable:

extension NT_Badge: Identifiable {  }

// MARK: - Equatable:

extension NT_Badge: Equatable {  }

// MARK: - Hashable:

extension NT_Badge: Hashable {  }

// MARK: - Example:

extension NT_Badge {
    
    // MARK: - Computed properties:
    
    /// An array of the example badges:
    static var example: [NT_Badge] {
        [
            .init(
                id: "Item.1",
                isShowingIcon: false,
                icon: Icons.mailStack,
                iconSymbolVariant: .fill,
                iconColor: .white,
                iconGradientStart: .blueGradientStart,
                iconGradientEnd: .blueGradientEnd,
                isIconColorGradient: false,
                title: "Item - 1",
                isTitleLocalized: true,
                titleTextCase: .uppercase,
                titleAlignment: .center,
                titleColor: .white,
                titleGradientStart: .blueGradientStart,
                titleGradientEnd: .blueGradientEnd,
                isTitleColorGradient: false,
                backgroundColor: .blue,
                backgroundGradientStart: .blueGradientStart,
                backgroundGradientEnd: .blueGradientEnd,
                isBackgroundColorGradient: true,
                isShowingBorder: true,
                borderColor: .init(.secondarySystemGroupedBackground),
                size: .small
            ),
            .init(
                id: "Item.2",
                isShowingIcon: false,
                icon: Icons.mailStack,
                iconSymbolVariant: .fill,
                iconColor: .white,
                iconGradientStart: .blueGradientStart,
                iconGradientEnd: .blueGradientEnd,
                isIconColorGradient: false,
                title: "Item - 2",
                isTitleLocalized: true,
                titleTextCase: .uppercase,
                titleAlignment: .center,
                titleColor: .white,
                titleGradientStart: .blueGradientStart,
                titleGradientEnd: .blueGradientEnd,
                isTitleColorGradient: false,
                backgroundColor: .orange,
                backgroundGradientStart: .orangeGradientStart,
                backgroundGradientEnd: .orangeGradientEnd,
                isBackgroundColorGradient: true,
                isShowingBorder: true,
                borderColor: .init(.secondarySystemGroupedBackground),
                size: .small
            ),
            .init(
                id: "Item.3",
                isShowingIcon: false,
                icon: Icons.mailStack,
                iconSymbolVariant: .fill,
                iconColor: .white,
                iconGradientStart: .blueGradientStart,
                iconGradientEnd: .blueGradientEnd,
                isIconColorGradient: false,
                title: "Item - 3",
                isTitleLocalized: true,
                titleTextCase: .uppercase,
                titleAlignment: .center,
                titleColor: .white,
                titleGradientStart: .blueGradientStart,
                titleGradientEnd: .blueGradientEnd,
                isTitleColorGradient: false,
                backgroundColor: .purple,
                backgroundGradientStart: .purpleGradientStart,
                backgroundGradientEnd: .purpleGradientEnd,
                isBackgroundColorGradient: true,
                isShowingBorder: true,
                borderColor: .init(.secondarySystemGroupedBackground),
                size: .small
            )
        ]
    }
}
