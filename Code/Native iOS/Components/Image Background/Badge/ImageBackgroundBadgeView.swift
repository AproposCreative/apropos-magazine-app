//
//  ImageBackgroundBadgeView.swift
//  Native
//

import SwiftUI

struct ImageBackgroundBadgeView: View {
    
    // MARK: - Private properties:
    
    /// An actual image to display:
    private let image: Image
    
    /// 'Bool' value indicating whether or not the image should be resizable or if it should just keep its original size:
    private let isImageResizable: Bool
    
    /// 'Bool' value indicating whether or not the image should be clipped based on its frame:
    private let isImageClipped: Bool
    
    /// Width of the image if applicable:
    private let imageWidth: CGFloat?
    
    /// Height of the image if applicable:
    private let imageHeight: CGFloat?
    
    /// Maximum width that the image should have if applicable:
    private let imageMaxWidth: CGFloat?
    
    /// Alignment of the image:
    private let imageAlignment: Alignment
    
    /// 'Bool' value indicating whether or not the image should take the full width:
    private let isImageFullWidth: Bool
    
    /// 'Bool' value indicating whether or not the background of the image should be shown at all:
    private let isShowingImageBackground: Bool
    
    /// Color of the background of the image:
    private let imageBackgroundColor: Color
    
    /// Starting color of the gradient of the background of the image if applicable:
    private let imageBackgroundGradientStart: Color
    
    /// Ending color of the gradient of the background of the image if applicable:
    private let imageBackgroundGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the background color of the image should have a gradient applied to it:
    private let isImageBackgroundColorGradient: Bool
    
    /// Radius of the rounded corners of the image:
    private let imageCornerRadius: Double
    
    /// Style of the rounded corners of the image:
    private let imageCornerStyle: RoundedCornerStyle
    
    /// Width of the border of the image:
    private let imageBorderWidth: Double
    
    /// Color of the border of the image:
    private let imageBorderColor: Color
    
    /// Accessibility label of the image:
    private let imageAccessibilityLabel: String
    
    /// 'Bool' value indicating whether or not the accessibility label of the image should be localized:
    private let isImageAccessibilityLabelLocalized: Bool
    
    /// 'Bool' value indicating whether or not the badge should be shown at all:
    private let isShowingBadge: Bool
    
    /// 'Bool' value indicating whether or not the icon of the badge should be shown at all:
    private let isShowingBadgeIcon: Bool
    
    /// An actual icon of the badge to display if applicable:
    private let badgeIcon: String
    
    /// Symbol variant of the icon of the badge if applicable (It could be '.fill', '.circle', etc.):
    private let badgeIconSymbolVariant: SymbolVariants
    
    /// Color of the icon of the badge if applicable:
    private let badgeIconColor: Color
    
    /// Starting color of the gradient of the icon of the badge if applicable:
    private let badgeIconGradientStart: Color
    
    /// Ending color of the gradient of the icon of the badge if applicable:
    private let badgeIconGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the icon of the badge should have a gradient applied to it if applicable:
    private let isBadgeIconColorGradient: Bool
    
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
    
    /// Starting color of the gradient of the title of the badge if applicable:
    private let badgeTitleGradientStart: Color
    
    /// Ending color of the gradient of the title of the badge if applicable:
    private let badgeTitleGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the title of the badge should have a gradient applied to it:
    private let isBadgeTitleColorGradient: Bool
    
    /// Background color of the badge:
    private let badgeBackgroundColor: Color
    
    /// Starting color of the gradient of the background of the badge if applicable:
    private let badgeBackgroundGradientStart: Color
    
    /// Ending color of the gradient of the background of the badge if applicable:
    private let badgeBackgroundGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the background of the badge should have a gradient applied to it:
    private let isBadgeBackgroundColorGradient: Bool
    
    /// 'Bool' value indicating whether or not the border of the badge should be shown at all:
    private let isShowingBadgeBorder: Bool
    
    /// Color of the border of the badge:
    private let badgeBorderColor: Color
    
    /// Size of the badge:
    private let badgeSize: NT_BadgeSize
    
    /// Alignment of the badge:
    private let badgeAlignment: Alignment
    
    /// Vertical padding around the badge:
    private let badgeVerticalPadding: Double
    
    /// Horizontal padding around the badge:
    private let badgeHorizontalPadding: Double
    
    /// Offset of the badge on the X-axis:
    private let badgeXAxisOffset: Double
    
    /// Offset of the badge on the Y-axis:
    private let badgeYAxisOffset: Double
    
    /// Action of the image after single tapping on it if applicable:
    private let imageSingleTapAction: (() -> ())?
    
    /// Action of the image after double tapping on it if applicable:
    private let imageDoubleTapAction: (() -> ())?
    
    init(
        image: Image,
        isImageResizable: Bool = true,
        isImageClipped: Bool = true,
        imageWidth: CGFloat? = 304,
        imageHeight: CGFloat? = 168,
        imageMaxWidth: CGFloat? = nil,
        imageAlignment: Alignment = .center,
        isImageFullWidth: Bool = true,
        isShowingImageBackground: Bool = false,
        imageBackgroundColor: Color = .accent,
        imageBackgroundGradientStart: Color = .blueGradientStart,
        imageBackgroundGradientEnd: Color = .blueGradientEnd,
        isImageBackgroundColorGradient: Bool = true,
        imageCornerRadius: Double = 12,
        imageCornerStyle: RoundedCornerStyle = .continuous,
        imageBorderWidth: Double = 0,
        imageBorderColor: Color = .init(.secondarySystemGroupedBackground),
        imageAccessibilityLabel: String = "",
        isImageAccessibilityLabelLocalized: Bool = true,
        isShowingBadge: Bool = true,
        isShowingBadgeIcon: Bool = false,
        badgeIcon: String = Icons.mailStack,
        badgeIconSymbolVariant: SymbolVariants = .fill,
        badgeIconColor: Color = .accent,
        badgeIconGradientStart: Color = .blueGradientStart,
        badgeIconGradientEnd: Color = .blueGradientEnd,
        isBadgeIconColorGradient: Bool = true,
        badgeTitle: String,
        isBadgeTitleLocalized: Bool = true,
        badgeTitleTextCase: Text.Case? = .uppercase,
        badgeTitleAlignment: TextAlignment = .center,
        badgeTitleColor: Color = .white,
        badgeTitleGradientStart: Color = .blueGradientStart,
        badgeTitleGradientEnd: Color = .blueGradientEnd,
        isBadgeTitleColorGradient: Bool = false,
        badgeBackgroundColor: Color = .init(.systemGroupedBackground),
        badgeBackgroundGradientStart: Color = .blueGradientStart,
        badgeBackgroundGradientEnd: Color = .blueGradientEnd,
        isBadgeBackgroundColorGradient: Bool = true,
        isShowingBadgeBorder: Bool = true,
        badgeBorderColor: Color = .init(.secondarySystemGroupedBackground),
        badgeSize: NT_BadgeSize = .small,
        badgeAlignment: Alignment = .topTrailing,
        badgeVerticalPadding: Double = 0,
        badgeHorizontalPadding: Double = 0,
        badgeXAxisOffset: Double = 8,
        badgeYAxisOffset: Double = 8,
        imageSingleTapAction: (() -> ())? = nil,
        imageDoubleTapAction: (() -> ())? = nil
    ) {
        
        /// Properties initialization:
        self.image = image
        self.isImageResizable = isImageResizable
        self.isImageClipped = isImageClipped
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.imageMaxWidth = imageMaxWidth
        self.imageAlignment = imageAlignment
        self.isImageFullWidth = isImageFullWidth
        self.isShowingImageBackground = isShowingImageBackground
        self.imageBackgroundColor = imageBackgroundColor
        self.imageBackgroundGradientStart = imageBackgroundGradientStart
        self.imageBackgroundGradientEnd = imageBackgroundGradientEnd
        self.isImageBackgroundColorGradient = isImageBackgroundColorGradient
        self.imageCornerRadius = imageCornerRadius
        self.imageCornerStyle = imageCornerStyle
        self.imageBorderWidth = imageBorderWidth
        self.imageBorderColor = imageBorderColor
        self.imageAccessibilityLabel = imageAccessibilityLabel
        self.isImageAccessibilityLabelLocalized = isImageAccessibilityLabelLocalized
        self.isShowingBadge = isShowingBadge
        self.isShowingBadgeIcon = isShowingBadgeIcon
        self.badgeIcon = badgeIcon
        self.badgeIconSymbolVariant = badgeIconSymbolVariant
        self.badgeIconColor = badgeIconColor
        self.badgeIconGradientStart = badgeIconGradientStart
        self.badgeIconGradientEnd = badgeIconGradientEnd
        self.isBadgeIconColorGradient = isBadgeIconColorGradient
        self.badgeTitle = badgeTitle
        self.isBadgeTitleLocalized = isBadgeTitleLocalized
        self.badgeTitleTextCase = badgeTitleTextCase
        self.badgeTitleAlignment = badgeTitleAlignment
        self.badgeTitleColor = badgeTitleColor
        self.badgeTitleGradientStart = badgeTitleGradientStart
        self.badgeTitleGradientEnd = badgeTitleGradientEnd
        self.isBadgeTitleColorGradient = isBadgeTitleColorGradient
        self.badgeBackgroundColor = badgeBackgroundColor
        self.badgeBackgroundGradientStart = badgeBackgroundGradientStart
        self.badgeBackgroundGradientEnd = badgeBackgroundGradientEnd
        self.isBadgeBackgroundColorGradient = isBadgeBackgroundColorGradient
        self.isShowingBadgeBorder = isShowingBadgeBorder
        self.badgeBorderColor = badgeBorderColor
        self.badgeSize = badgeSize
        self.badgeAlignment = badgeAlignment
        self.badgeVerticalPadding = badgeVerticalPadding
        self.badgeHorizontalPadding = badgeHorizontalPadding
        self.badgeXAxisOffset = badgeXAxisOffset
        self.badgeYAxisOffset = badgeYAxisOffset
        self.imageSingleTapAction = imageSingleTapAction
        self.imageDoubleTapAction = imageDoubleTapAction
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .overlay(alignment: badgeAlignment) {
                badge
            }
    }
}

// MARK: - Item:

private extension ImageBackgroundBadgeView {
    private var item: some View {
        ImageBackgroundView(
            image: image,
            isResizable: isImageResizable,
            isClipped: isImageClipped,
            width: imageWidth,
            height: imageHeight,
            maxWidth: imageMaxWidth,
            alignment: imageAlignment,
            isFullWidth: isImageFullWidth,
            isShowingBackground: isShowingImageBackground,
            backgroundColor: imageBackgroundColor,
            backgroundGradientStart: imageBackgroundGradientStart,
            backgroundGradientEnd: imageBackgroundGradientEnd,
            isBackgroundColorGradient: isImageBackgroundColorGradient,
            cornerRadius: imageCornerRadius,
            cornerStyle: imageCornerStyle,
            borderWidth: imageBorderWidth,
            borderColor: imageBorderColor,
            accessibilityLabel: imageAccessibilityLabel,
            isAccessibilityLabelLocalized: isImageAccessibilityLabelLocalized,
            singleTapAction: imageSingleTapAction,
            doubleTapAction: imageDoubleTapAction
        )
    }
}

// MARK: - Badge:

private extension ImageBackgroundBadgeView {
    @ViewBuilder
    private var badge: some View {
        if isShowingBadge {
            badgeContent
        }
    }
    
    private var badgeContent: some View {
        badgeItem
            .padding(
                .vertical,
                badgeVerticalPadding
            )
            .padding(
                .vertical,
                badgeHorizontalPadding
            )
            .offset(
                x: badgeXAxisOffset,
                y: badgeYAxisOffset
            )
    }
    
    private var badgeItem: some View {
        BadgeView(
            isShowingIcon: isShowingBadgeIcon,
            icon: badgeIcon,
            iconSymbolVariant: badgeIconSymbolVariant,
            iconColor: badgeIconColor,
            iconGradientStart: badgeIconGradientStart,
            iconGradientEnd: badgeIconGradientEnd,
            isIconColorGradient: isBadgeIconColorGradient,
            title: badgeTitle,
            isTitleLocalized: isBadgeTitleLocalized,
            titleTextCase: badgeTitleTextCase,
            titleAlignment: badgeTitleAlignment,
            titleColor: badgeTitleColor,
            titleGradientStart: badgeTitleGradientStart,
            titleGradientEnd: badgeTitleGradientEnd,
            isTitleColorGradient: isBadgeTitleColorGradient,
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
    ImageBackgroundBadgeView(
        image: .init(.productDetails2),
        isImageResizable: true,
        isImageClipped: true,
        imageWidth: 304,
        imageHeight: 168,
        imageMaxWidth: nil,
        imageAlignment: .center,
        isImageFullWidth: true,
        isShowingImageBackground: false,
        imageBackgroundColor: .accent,
        imageBackgroundGradientStart: .blueGradientStart,
        imageBackgroundGradientEnd: .blueGradientEnd,
        isImageBackgroundColorGradient: true,
        imageCornerRadius: 12,
        imageCornerStyle: .continuous,
        imageBorderWidth: 0,
        imageBorderColor: .init(.secondarySystemGroupedBackground),
        imageAccessibilityLabel: "",
        isImageAccessibilityLabelLocalized: true,
        isShowingBadge: true,
        isShowingBadgeIcon: false,
        badgeIcon: Icons.mailStack,
        badgeIconSymbolVariant: .fill,
        badgeIconColor: .blue,
        badgeIconGradientStart: .blueGradientStart,
        badgeIconGradientEnd: .blueGradientEnd,
        isBadgeIconColorGradient: true,
        badgeTitle: "Badge",
        isBadgeTitleLocalized: true,
        badgeTitleTextCase: .uppercase,
        badgeTitleAlignment: .center,
        badgeTitleColor: .white,
        badgeTitleGradientStart: .blueGradientStart,
        badgeTitleGradientEnd: .blueGradientEnd,
        isBadgeTitleColorGradient: false,
        badgeBackgroundColor: .init(.systemGroupedBackground),
        badgeBackgroundGradientStart: .blueGradientStart,
        badgeBackgroundGradientEnd: .blueGradientEnd,
        isBadgeBackgroundColorGradient: true,
        isShowingBadgeBorder: true,
        badgeBorderColor: .init(.secondarySystemGroupedBackground),
        badgeSize: .small,
        badgeAlignment: .topTrailing,
        badgeVerticalPadding: 0,
        badgeHorizontalPadding: 0,
        badgeXAxisOffset: 8,
        badgeYAxisOffset: 8
    ) {
        
    } imageDoubleTapAction: {
        
    }
    .padding()
}
