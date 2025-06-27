//
//  IconBackgroundView.swift
//  Native
//

import SwiftUI

struct IconBackgroundView: View {
    
    // MARK: - Private properties:
    
    /// An actual icon to display:
    private let icon: String
    
    /// Symbol variant of the icon (It could be '.fill', '.circle', etc.):
    private let symbolVariant: SymbolVariants
    
    /// Color of the icon:
    private let color: Color
    
    /// Starting color of the gradient of the icon if applicable:
    private let gradientStart: Color
    
    /// Ending color of the gradient of the icon if applicable:
    private let gradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the icon should have a gradient applied to it:
    private let isColorGradient: Bool
    
    /// 'Bool' value indicating whether or not the background of the icon should be shown at all:
    private let isShowingBackground: Bool
    
    /// 'Bool' value indicating whether or not the icon should take the full width:
    private let isFullWidth: Bool
    
    /// Color of the background of the icon:
    private let backgroundColor: Color
    
    /// Starting color of the gradient of the background of the icon if applicable:
    private let backgroundGradientStart: Color
    
    /// Ending color of the gradient of the background of the icon if applicable:
    private let backgroundGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the background color of the icon should have a gradient applied to it:
    private let isBackgroundColorGradient: Bool
    
    /// 'Bool' value indicating whether or not the background of the icon should have a circular shape:
    private let isCircularBackground: Bool
    
    /// Size of the icon:
    private let size: NT_IconSize
    
    /// Width of the border of the icon:
    private let borderWidth: Double
    
    /// Color of the border of the icon:
    private let borderColor: Color
    
    /// 'Bool' value indicating whether or not the badge of the icon should be shown at all:
    private let isShowingBadge: Bool
    
    /// Icon of the badge of the icon:
    private let badgeIcon: String
    
    /// Symbol variant of the badge of the icon (It could be '.fill', '.circle', etc.):
    private let badgeSymbolVariant: SymbolVariants
    
    /// Font of the badge of the icon:
    private let badgeFont: Font
    
    /// Color of the badge of the icon:
    private let badgeColor: Color
    
    /// Starting color of the gradient of the badge of the icon if applicable:
    private let badgeGradientStart: Color
    
    /// Ending color of the gradient of the badge of the icon if applicable:
    private let badgeGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the badge of the icon should have a gradient applied to it:
    private let isBadgeColorGradient: Bool
    
    /// Size of the frame of the badge of the icon:
    private let badgeFrame: Double
    
    /// Color of the background of the badge of the icon:
    private let badgeBackgroundColor: Color
    
    /// Starting color of the gradient of the background of the badge of the icon if applicable:
    private let badgeBackgroundGradientStart: Color
    
    /// Ending color of the gradient of the background of the badge of the icon if applicable:
    private let badgeBackgroundGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the background color of the badge of the icon should have a gradient applied to it:
    private let isBadgeBackgroundColorGradient: Bool
    
    /// 'Bool' value indicating whether or not the badge of the icon should have a circular shape:
    private let isBadgeCircularBackground: Bool
    
    /// Radius of the rounded corners of the badge of the icon:
    private let badgeCornerRadius: Double
    
    /// Style of the rounded corners of the badge of the icon:
    private let badgeCornerStyle: RoundedCornerStyle
    
    /// Alignment of the badge of the icon:
    private let badgeAlignment: Alignment
    
    /// Width of the border of the badge of the icon:
    private let badgeBorderWidth: Double
    
    /// Color of the border of the badge of the icon:
    private let badgeBorderColor: Color
    
    /// 'Bool' value indicating whether or not the icon is displayed in the sidebar which is needed to handle its tint color correctly:
    private let isSidebar: Bool
    
    /// Action of the icon after single tapping on it if applicable:
    private let singleTapAction: (() -> ())?
    
    /// Action of the icon after double tapping on it if applicable:
    private let doubleTapAction: (() -> ())?
    
    init(
        icon: String,
        symbolVariant: SymbolVariants = .fill,
        color: Color = .white,
        gradientStart: Color = .blueGradientStart,
        gradientEnd: Color = .blueGradientEnd,
        isColorGradient: Bool = false,
        isShowingBackground: Bool = true,
        isFullWidth: Bool = false,
        backgroundColor: Color = .accent,
        backgroundGradientStart: Color = .blueGradientStart,
        backgroundGradientEnd: Color = .blueGradientEnd,
        isBackgroundColorGradient: Bool = true,
        isCircularBackground: Bool = false,
        size: NT_IconSize = .fortyEightPixels,
        borderWidth: Double = 0,
        borderColor: Color = .init(.secondarySystemGroupedBackground),
        isShowingBadge: Bool = false,
        badgeIcon: String = Icons.mailStack,
        badgeSymbolVariant: SymbolVariants = .fill,
        badgeFont: Font = .system(
            size: 10,
            weight: .regular,
            design: .default
        ),
        badgeColor: Color = .white,
        badgeGradientStart: Color = .blueGradientStart,
        badgeGradientEnd: Color = .blueGradientEnd,
        isBadgeColorGradient: Bool = false,
        badgeFrame: Double = 20,
        badgeBackgroundColor: Color = .accent,
        badgeBackgroundGradientStart: Color = .blueGradientStart,
        badgeBackgroundGradientEnd: Color = .blueGradientEnd,
        isBadgeBackgroundColorGradient: Bool = true,
        isBadgeCircularBackground: Bool = false,
        badgeCornerRadius: Double = 6,
        badgeCornerStyle: RoundedCornerStyle = .continuous,
        badgeAlignment: Alignment = .bottomTrailing,
        badgeBorderWidth: Double = 2,
        badgeBorderColor: Color = .init(.secondarySystemGroupedBackground),
        isSidebar: Bool = false,
        singleTapAction: (() -> ())? = nil,
        doubleTapAction: (() -> ())? = nil
    ) {
        
        /// Properties initialization:
        self.icon = icon
        self.symbolVariant = symbolVariant
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.isColorGradient = isColorGradient
        self.isShowingBackground = isShowingBackground
        self.isFullWidth = isFullWidth
        self.backgroundColor = backgroundColor
        self.backgroundGradientStart = backgroundGradientStart
        self.backgroundGradientEnd = backgroundGradientEnd
        self.isBackgroundColorGradient = isBackgroundColorGradient
        self.isCircularBackground = isCircularBackground
        self.size = size
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.isShowingBadge = isShowingBadge
        self.badgeIcon = badgeIcon
        self.badgeSymbolVariant = badgeSymbolVariant
        self.badgeFont = badgeFont
        self.badgeColor = badgeColor
        self.badgeGradientStart = badgeGradientStart
        self.badgeGradientEnd = badgeGradientEnd
        self.isBadgeColorGradient = isBadgeColorGradient
        self.badgeFrame = badgeFrame
        self.badgeBackgroundColor = badgeBackgroundColor
        self.badgeBackgroundGradientStart = badgeBackgroundGradientStart
        self.badgeBackgroundGradientEnd = badgeBackgroundGradientEnd
        self.isBadgeBackgroundColorGradient = isBadgeBackgroundColorGradient
        self.isBadgeCircularBackground = isBadgeCircularBackground
        self.badgeCornerRadius = badgeCornerRadius
        self.badgeCornerStyle = badgeCornerStyle
        self.badgeAlignment = badgeAlignment
        self.badgeBorderWidth = badgeBorderWidth
        self.badgeBorderColor = badgeBorderColor
        self.isSidebar = isSidebar
        self.singleTapAction = singleTapAction
        self.doubleTapAction = doubleTapAction
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the icon has actions applied to it:
    private var doesHaveActions: Bool {
        singleTapAction != nil
        || doubleTapAction != nil
    }
    
    /// Font of the icon that is based on its size and whether or not it should have a background:
    private var font: Font {
        if isShowingBackground {
            return size.font
        } else {
            return size.nonBackgroundFont
        }
    }
    
    /// Content of the color of the background of the icon:
    private var backgroundColorContent: Color {
        if isShowingBackground {
            return backgroundColor
        } else {
            return .clear
        }
    }
    
    /// Content of the starting color of the gradient of the background of the icon:
    private var backgroundGradientStartContent: Color {
        if isShowingBackground {
            return backgroundGradientStart
        } else {
            return .clear
        }
    }
    
    /// Content of the ending color of the gradient of the background of the icon:
    private var backgroundGradientEndContent: Color {
        if isShowingBackground {
            return backgroundGradientEnd
        } else {
            return .clear
        }
    }
    
    /// Size of the frame of the icon that is based on its size:
    private var frame: CGFloat? {
        size.frame
    }
    
    /// Content of the width of the icon based on whether or not it should take the full width:
    private var widthContent: CGFloat? {
        isFullWidth ? nil : frame
    }
    
    /// Maximum width of the icon based on whether or not it should take the full width if applicable:
    private var maxWidth: CGFloat? {
        isFullWidth ? .infinity : nil
    }
    
    /// Radius of the rounded corners of the icon that is based on its size:
    private var cornerRadius: Double {
        if isShowingBackground,
           let frame {
            return isCircularBackground ? frame / 2 : size.cornerRadius
        } else {
            return 0
        }
    }

    /// Style of the rounded corners of the icon that is based on its size:
    private var cornerStyle: RoundedCornerStyle {
        size.cornerStyle
    }
    
    /// Content of the radius of the rounded corners of the badge of the icon:
    private var badgeCornerRadiusContent: Double {
        isBadgeCircularBackground ? badgeFrame / 2 : badgeCornerRadius
    }
    
    /// Accessibility traits of the icon if it has actions applied to it to indicate that it's an actual button:
    private var accessibilityTraits: AccessibilityTraits {
        doesHaveActions ? .isButton : []
    }
    
    /// Accessibility child behavior of the icon that is based on whether or not it has actions applied to it:
    private var accessibilityChildBehavior: AccessibilityChildBehavior {
        doesHaveActions ? .combine : .ignore
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        Image(systemName: icon)
            .symbolVariant(symbolVariant)
            .font(font)
            .foregroundGradient(
                color: color,
                gradientStart: gradientStart,
                gradientEnd: gradientEnd,
                isGradient: isColorGradient,
                isSidebar: isSidebar
            )
            .frame(
                width: widthContent,
                height: frame,
                alignment: .center
            )
            .frame(
                minWidth: frame,
                maxWidth: maxWidth,
                alignment: .center
            )
            .gradientBackground(
                color: backgroundColorContent,
                gradientStart: backgroundGradientStartContent,
                gradientEnd: backgroundGradientEndContent,
                isGradient: isBackgroundColorGradient
            )
            .roundedCorners(
                cornerRadius: cornerRadius,
                cornerStyle: cornerStyle
            )
            .overlay(border)
            .overlay(alignment: badgeAlignment) {
                badge
            }
            .optionalTapGesture(
                count: 2,
                action: doubleTapAction
            )
            .optionalTapGesture(
                count: 1,
                action: singleTapAction
            )
            .accessibilityAddTraits(accessibilityTraits)
            .accessibilityElement(children: accessibilityChildBehavior)
    }
}

// MARK: - Border:

private extension IconBackgroundView {
    private var border: some View {
        RoundedRectangle(
            cornerRadius: cornerRadius,
            style: cornerStyle
        )
        .stroke(
            borderColor,
            lineWidth: borderWidth
        )
    }
}

// MARK: - Badge:

private extension IconBackgroundView {
    @ViewBuilder
    private var badge: some View {
        if isShowingBadge {
            badgeContent
        }
    }
    
    private var badgeContent: some View {
        Image(systemName: badgeIcon)
            .symbolVariant(badgeSymbolVariant)
            .font(badgeFont)
            .foregroundGradient(
                color: badgeColor,
                gradientStart: badgeGradientStart,
                gradientEnd: badgeGradientEnd,
                isGradient: isBadgeColorGradient,
                isSidebar: isSidebar
            )
            .frame(
                width: badgeFrame,
                height: badgeFrame,
                alignment: .center
            )
            .gradientBackground(
                color: badgeBackgroundColor,
                gradientStart: badgeBackgroundGradientStart,
                gradientEnd: badgeBackgroundGradientEnd,
                isGradient: isBadgeBackgroundColorGradient
            )
            .roundedCorners(
                cornerRadius: badgeCornerRadiusContent,
                cornerStyle: badgeCornerStyle
            )
            .overlay(badgeBorder)
    }
    
    private var badgeBorder: some View {
        RoundedRectangle(
            cornerRadius: badgeCornerRadiusContent,
            style: badgeCornerStyle
        )
        .stroke(
            badgeBorderColor,
            lineWidth: badgeBorderWidth
        )
    }
}

// MARK: - Preview:

#Preview {
    IconBackgroundView(
        icon: Icons.mailStack,
        symbolVariant: .fill,
        color: .white,
        gradientStart: .blueGradientStart,
        gradientEnd: .blueGradientEnd,
        isColorGradient: false,
        isShowingBackground: true,
        isFullWidth: false,
        backgroundColor: .accent,
        backgroundGradientStart: .blueGradientStart,
        backgroundGradientEnd: .blueGradientEnd,
        isBackgroundColorGradient: true,
        isCircularBackground: false,
        size: .fortyEightPixels,
        borderWidth: 0,
        borderColor: .init(.secondarySystemGroupedBackground),
        isShowingBadge: true,
        badgeIcon: Icons.mailStack,
        badgeSymbolVariant: .fill,
        badgeFont: .system(
            size: 10,
            weight: .regular,
            design: .default
        ),
        badgeColor: .white,
        badgeGradientStart: .blueGradientStart,
        badgeGradientEnd: .blueGradientEnd,
        isBadgeColorGradient: false,
        badgeFrame: 20,
        badgeBackgroundColor: .accent,
        badgeBackgroundGradientStart: .blueGradientStart,
        badgeBackgroundGradientEnd: .blueGradientEnd,
        isBadgeBackgroundColorGradient: true,
        isBadgeCircularBackground: false,
        badgeCornerRadius: 6,
        badgeCornerStyle: .continuous,
        badgeAlignment: .bottomTrailing,
        badgeBorderWidth: 2,
        badgeBorderColor: .init(.secondarySystemGroupedBackground),
        isSidebar: false
    ) {
        
    } doubleTapAction: {
        
    }
    .padding()
    .frame(
        maxWidth: .infinity,
        maxHeight: .infinity,
        alignment: .center
    )
    .background(Color(.systemGroupedBackground))
}
