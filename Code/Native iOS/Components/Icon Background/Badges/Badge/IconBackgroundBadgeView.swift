//
//  IconBackgroundBadgeView.swift
//  Native
//

import SwiftUI

struct IconBackgroundBadgeView: View {
    
    // MARK: - Private properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    /// An actual icon to display:
    private let icon: String
    
    /// Symbol variant of the icon (It could be '.fill', '.circle', etc.):
    private let iconSymbolVariant: SymbolVariants
    
    /// Color of the icon:
    private let iconColor: Color
    
    /// Starting color of the gradient of the icon if applicable:
    private let iconGradientStart: Color
    
    /// Ending color of the gradient of the icon if applicable:
    private let iconGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the icon should have a gradient applied to it:
    private let isIconColorGradient: Bool
    
    /// 'Bool' value indicating whether or not the background of the icon should be shown at all:
    private let isShowingIconBackground: Bool
    
    /// Color of the background of the icon:
    private let iconBackgroundColor: Color
    
    /// Starting color of the gradient of the background of the icon if applicable:
    private let iconBackgroundGradientStart: Color
    
    /// Ending color of the gradient of the background of the icon if applicable:
    private let iconBackgroundGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the background color of the icon should have a gradient applied to it:
    private let isIconBackgroundColorGradient: Bool
    
    /// Size of the icon:
    private let iconSize: NT_IconSize
    
    /// 'Bool' value indicating whether or not the badge should be shown at all:
    private let isShowingBadge: Bool
    
    /// Title of the badge:
    private let badgeTitle: String
    
    /// 'Bool' value indicating whether or not the title of the badge should be localized:
    private let isBadgeTitleLocalized: Bool
    
    /// Text case of the title of the badge:
    private let badgeTitleTextCase: Text.Case?
    
    /// Alignment of the title of the badge:
    private let badgeTitleAlignment: TextAlignment
    
    /// Color of the title of the badge:
    private let badgeTitleColor: Color
    
    /// Background color of the badge:
    private let badgeBackgroundColor: Color
    
    /// Starting color of the gradient of the background of the badge if applicable:
    private let badgeBackgroundGradientStart: Color
    
    /// Ending color of the gradient of the background of the badge if applicable:
    private let badgeBackgroundGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the background color of the badge should have a gradient applied to it:
    private let isBadgeBackgroundColorGradient: Bool
    
    /// 'Bool' value indicating whether or not the border of the badge should be shown at all:
    private var isShowingBadgeBorder: Bool
    
    /// Color of the border of the badge:
    private let badgeBorderColor: Color
    
    /// Size of the badge:
    private let badgeSize: NT_BadgeSize
    
    /// Offset that the badge has on the X-axis:
    private let badgeXAxisOffset: Double
    
    /// Offset that the badge has on the Y-axis:
    private let badgeYAxisOffset: Double
    
    /// Alignment of the overlay with the badge:
    private let badgeAlignment: Alignment
    
    init(
        icon: String,
        iconSymbolVariant: SymbolVariants = .fill,
        iconColor: Color = .white,
        iconGradientStart: Color = .blueGradientStart,
        iconGradientEnd: Color = .blueGradientEnd,
        isIconColorGradient: Bool = false,
        isShowingIconBackground: Bool = true,
        iconBackgroundColor: Color = .blue,
        iconBackgroundGradientStart: Color = .blueGradientStart,
        iconBackgroundGradientEnd: Color = .blueGradientEnd,
        isIconBackgroundColorGradient: Bool = true,
        iconSize: NT_IconSize = .twoHundredPixels,
        isShowingBadge: Bool = true,
        badgeTitle: String,
        isBadgeTitleLocalized: Bool = true,
        badgeTitleTextCase: Text.Case? = .uppercase,
        badgeTitleAlignment: TextAlignment = .center,
        badgeTitleColor: Color = .white,
        badgeBackgroundColor: Color = .blue,
        badgeBackgroundGradientStart: Color = .blueGradientStart,
        badgeBackgroundGradientEnd: Color = .blueGradientEnd,
        isBadgeBackgroundColorGradient: Bool = true,
        isShowingBadgeBorder: Bool = true,
        badgeBorderColor: Color = .init(.systemBackground),
        badgeSize: NT_BadgeSize = .large,
        badgeXAxisOffset: Double = 24,
        badgeYAxisOffset: Double = 12,
        badgeAlignment: Alignment = .topTrailing
    ) {
        
        /// Properties initialization:
        self.icon = icon
        self.iconSymbolVariant = iconSymbolVariant
        self.iconColor = iconColor
        self.iconGradientStart = iconGradientStart
        self.iconGradientEnd = iconGradientEnd
        self.isIconColorGradient = isIconColorGradient
        self.isShowingIconBackground = isShowingIconBackground
        self.iconBackgroundColor = iconBackgroundColor
        self.iconBackgroundGradientStart = iconBackgroundGradientStart
        self.iconBackgroundGradientEnd = iconBackgroundGradientEnd
        self.isIconBackgroundColorGradient = isIconBackgroundColorGradient
        self.iconSize = iconSize
        self.isShowingBadge = isShowingBadge
        self.badgeTitle = badgeTitle
        self.isBadgeTitleLocalized = isBadgeTitleLocalized
        self.badgeTitleTextCase = badgeTitleTextCase
        self.badgeTitleAlignment = badgeTitleAlignment
        self.badgeTitleColor = badgeTitleColor
        self.badgeBackgroundColor = badgeBackgroundColor
        self.badgeBackgroundGradientStart = badgeBackgroundGradientStart
        self.badgeBackgroundGradientEnd = badgeBackgroundGradientEnd
        self.isBadgeBackgroundColorGradient = isBadgeBackgroundColorGradient
        self.isShowingBadgeBorder = isShowingBadgeBorder
        self.badgeBorderColor = badgeBorderColor
        self.badgeSize = badgeSize
        self.badgeXAxisOffset = badgeXAxisOffset
        self.badgeYAxisOffset = badgeYAxisOffset
        self.badgeAlignment = badgeAlignment
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    private var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Item:

private extension IconBackgroundBadgeView {
    @ViewBuilder
    private var item: some View {
        if shouldMoveContent {
            verticalItem
        } else {
            overlayItem
        }
    }
    
    private var overlayItem: some View {
        iconContent
            .overlay(alignment: badgeAlignment) {
                badge
            }
    }
    
    private var verticalItem: some View {
        VStack(
            alignment: .center,
            spacing: 12
        ) {
            verticalItemContent
        }
    }
    
    @ViewBuilder
    private var verticalItemContent: some View {
        iconContent
        badge
    }
}

// MARK: - Icon:

private extension IconBackgroundBadgeView {
    private var iconContent: some View {
        IconBackgroundView(
            icon: icon,
            symbolVariant: iconSymbolVariant,
            color: iconColor,
            gradientStart: iconGradientStart,
            gradientEnd: iconGradientEnd,
            isColorGradient: isIconColorGradient,
            isShowingBackground: isShowingIconBackground,
            backgroundColor: iconBackgroundColor,
            backgroundGradientStart: iconBackgroundGradientStart,
            backgroundGradientEnd: iconBackgroundGradientEnd,
            isBackgroundColorGradient: isIconBackgroundColorGradient,
            size: iconSize
        )
    }
}

// MARK: - Badge:

private extension IconBackgroundBadgeView {
    @ViewBuilder
    private var badge: some View {
        if isShowingBadge {
            badgeContent
        }
    }
    
    @ViewBuilder
    private var badgeContent: some View {
        if shouldMoveContent {
            badgeItemContent
        } else {
            badgeItem
        }
    }
    
    private var badgeItem: some View {
        badgeItemContent
            .offset(
                x: badgeXAxisOffset,
                y: badgeYAxisOffset
            )
    }
    
    private var badgeItemContent: some View {
        BadgeView(
            title: badgeTitle,
            isTitleLocalized: isBadgeTitleLocalized,
            titleTextCase: badgeTitleTextCase,
            titleAlignment: badgeTitleAlignment,
            titleColor: badgeTitleColor,
            backgroundColor: badgeBackgroundColor,
            backgroundGradientStart: badgeBackgroundGradientStart,
            backgroundGradientEnd: badgeBackgroundGradientEnd,
            isBackgroundColorGradient: isBadgeBackgroundColorGradient,
            isShowingBorder: isShowingBadgeBorder,
            borderColor: badgeBorderColor,
            size: badgeSize
        )
    }
}

// MARK: - Preview:

#Preview {
    IconBackgroundBadgeView(
        icon: Icons.chevronLeftForwardslashChevronRight,
        iconSymbolVariant: .fill,
        iconColor: .white,
        iconGradientStart: .blueGradientStart,
        iconGradientEnd: .blueGradientEnd,
        isIconColorGradient: false,
        isShowingIconBackground: true,
        iconBackgroundColor: .blue,
        iconBackgroundGradientStart: .blueGradientStart,
        iconBackgroundGradientEnd: .blueGradientEnd,
        isIconBackgroundColorGradient: true,
        iconSize: .thirtyTwoPixels,
        isShowingBadge: true,
        badgeTitle: "Title",
        isBadgeTitleLocalized: true,
        badgeTitleTextCase: .uppercase,
        badgeTitleAlignment: .center,
        badgeTitleColor: .white,
        badgeBackgroundColor: .blue,
        badgeBackgroundGradientStart: .blueGradientStart,
        badgeBackgroundGradientEnd: .blueGradientEnd,
        isBadgeBackgroundColorGradient: true,
        isShowingBadgeBorder: true,
        badgeBorderColor: .init(.systemBackground),
        badgeSize: .large,
        badgeXAxisOffset: 24,
        badgeYAxisOffset: 12,
        badgeAlignment: .topTrailing
    )
}
