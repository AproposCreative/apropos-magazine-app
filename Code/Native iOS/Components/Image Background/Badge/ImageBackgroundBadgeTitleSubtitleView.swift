//
//  ImageBackgroundBadgeTitleSubtitleView.swift
//  Native
//

import SwiftUI

struct ImageBackgroundBadgeTitleSubtitleView: View {
    
    // MARK: - Private properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
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
    
    /// 'Bool' value indicating whether or not the title should be shown at all:
    private let isShowingTitle: Bool
    
    /// An actual title to display:
    private let title: String
    
    /// 'Bool' value indicating whether or not the title should be localized:
    private let isTitleLocalized: Bool
    
    /// Font of the title:
    private let titleFont: Font
    
    /// Text case of the title:
    private let titleTextCase: Text.Case?
    
    /// Alignment of the title:
    private let titleAlignment: TextAlignment
    
    /// Additional spacing between the multiple lines of the title:
    private let titleLineSpacing: Double
    
    /// Maximum number of lines that the title can have if applicable:
    private let titleLineLimit: Int?
    
    /// Color of the title:
    private let titleColor: Color
    
    /// 'Bool' value indicating whether or not the subtitle should be shown at all:
    private let isShowingSubtitle: Bool
    
    /// An actual subtitle to display:
    private let subtitle: String
    
    /// 'Bool' value indicating whether or not the subtitle should be localized:
    private let isSubtitleLocalized: Bool
    
    /// Font of the subtitle:
    private let subtitleFont: Font
    
    /// Text case of the subtitle:
    private let subtitleTextCase: Text.Case?
    
    /// Alignment of the subtitle:
    private let subtitleAlignment: TextAlignment
    
    /// Additional spacing between the multiple lines of the subtitle:
    private let subtitleLineSpacing: Double
    
    /// Maximum number of lines that the subtitle can have if applicable:
    private let subtitleLineLimit: Int?
    
    /// Color of the subtitle:
    private let subtitleColor: Color
    
    /// Alignment of the title and the subtitle:
    private let titleSubtitleAlignment: HorizontalAlignment
    
    /// Spacing between the title and the subtitle:
    private let titleSubtitleSpacing: Double
    
    /// Maximum width of the title and the subtitle:
    private let titleSubtitleMaxWidth: CGFloat?
    
    /// Alignment of the title and the subtitle if they have a maximum width applied to it:
    private let titleSubtitleMaxWidthAlignment: Alignment
    
    /// Vertical padding around the title and the subtitle:
    private let titleSubtitleVerticalPadding: Double
    
    /// Horizontal padding around the title and the subtitle:
    private let titleSubtitleHorizontalPadding: Double
    
    /// 'Bool' value indicating whether or not the content of the view should be placed in reverse meaning that the title and the subtitle would be displayed first and the image last:
    private let isReversed: Bool
    
    /// Alignment of the content of the view:
    private let alignment: NT_Alignment
    
    /// Vertical alignment of the content of the view:
    private let verticalAlignment: VerticalAlignment
    
    /// Horizontal alignment of the content of the view:
    private let horizontalAlignment: HorizontalAlignment
    
    /// Spacing between the content of the view:
    private let spacing: Double
    
    /// Vertical padding around the content of the view:
    private let verticalPadding: Double
    
    /// Horizontal padding around the content of the view:
    private let horizontalPadding: Double
    
    /// Maximum height that the view can have if applicable:
    private let maxHeight: CGFloat?
    
    /// Alignment of the view if it has a maximum height applied to it:
    private let maxHeightAlignment: Alignment
    
    /// 'Bool' value indicating whether or not the background of the view should be shown at all:
    private let isShowingBackground: Bool
    
    /// Color of the background of the view:
    private let backgroundColor: Color
    
    /// Starting color of the gradient of the background of the view if applicable:
    private let backgroundGradientStart: Color
    
    /// Ending color of the gradient of the background of the view if applicable:
    private let backgroundGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the background of the view should have a gradient applied to it:
    private let isBackgroundColorGradient: Bool
    
    /// Radius of the rounded corners of the view:
    private let cornerRadius: Double
    
    /// Style of the rounded corners of the view:
    private let cornerStyle: RoundedCornerStyle
    
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
        isShowingTitle: Bool = true,
        title: String,
        isTitleLocalized: Bool = true,
        titleFont: Font = .headline,
        titleTextCase: Text.Case? = .none,
        titleAlignment: TextAlignment = .leading,
        titleLineSpacing: Double = 0,
        titleLineLimit: Int? = nil,
        titleColor: Color = .primary,
        isShowingSubtitle: Bool = true,
        subtitle: String,
        isSubtitleLocalized: Bool = true,
        subtitleFont: Font = .subheadline,
        subtitleTextCase: Text.Case? = .none,
        subtitleAlignment: TextAlignment = .leading,
        subtitleLineSpacing: Double = 0,
        subtitleLineLimit: Int? = nil,
        subtitleColor: Color = .secondary,
        titleSubtitleAlignment: HorizontalAlignment = .leading,
        titleSubtitleSpacing: Double = 4,
        titleSubtitleMaxWidth: CGFloat? = nil,
        titleSubtitleMaxWidthAlignment: Alignment = .leading,
        titleSubtitleVerticalPadding: Double = 0,
        titleSubtitleHorizontalPadding: Double = 0,
        isReversed: Bool = false,
        alignment: NT_Alignment = .vertical,
        verticalAlignment: VerticalAlignment = .top,
        horizontalAlignment: HorizontalAlignment = .leading,
        spacing: Double = 12,
        verticalPadding: Double = 12,
        horizontalPadding: Double = 12,
        maxHeight: CGFloat? = nil,
        maxHeightAlignment: Alignment = .topLeading,
        isShowingBackground: Bool = true,
        backgroundColor: Color = .init(.secondarySystemGroupedBackground),
        backgroundGradientStart: Color = .blueGradientStart,
        backgroundGradientEnd: Color = .blueGradientEnd,
        isBackgroundColorGradient: Bool = false,
        cornerRadius: Double = 16,
        cornerStyle: RoundedCornerStyle = .continuous,
        imageSingleTapAction: (() -> ())? = nil,
        imageDoubleTapAction: (() -> ())? = nil
    ) {
        
        /// Properties initialization:
        self.image = image
        self.isImageResizable = isImageResizable
        self.isImageClipped = isImageClipped
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
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
        self.isShowingTitle = isShowingTitle
        self.title = title
        self.isTitleLocalized = isTitleLocalized
        self.titleFont = titleFont
        self.titleTextCase = titleTextCase
        self.titleAlignment = titleAlignment
        self.titleLineSpacing = titleLineSpacing
        self.titleLineLimit = titleLineLimit
        self.titleColor = titleColor
        self.isShowingSubtitle = isShowingSubtitle
        self.subtitle = subtitle
        self.isSubtitleLocalized = isSubtitleLocalized
        self.subtitleFont = subtitleFont
        self.subtitleTextCase = subtitleTextCase
        self.subtitleAlignment = subtitleAlignment
        self.subtitleLineSpacing = subtitleLineSpacing
        self.subtitleLineLimit = subtitleLineLimit
        self.subtitleColor = subtitleColor
        self.titleSubtitleAlignment = titleSubtitleAlignment
        self.titleSubtitleSpacing = titleSubtitleSpacing
        self.titleSubtitleMaxWidth = titleSubtitleMaxWidth
        self.titleSubtitleMaxWidthAlignment = titleSubtitleMaxWidthAlignment
        self.titleSubtitleVerticalPadding = titleSubtitleVerticalPadding
        self.titleSubtitleHorizontalPadding = titleSubtitleHorizontalPadding
        self.isReversed = isReversed
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
        self.horizontalAlignment = horizontalAlignment
        self.spacing = spacing
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
        self.maxHeight = maxHeight
        self.maxHeightAlignment = maxHeightAlignment
        self.isShowingBackground = isShowingBackground
        self.backgroundColor = backgroundColor
        self.backgroundGradientStart = backgroundGradientStart
        self.backgroundGradientEnd = backgroundGradientEnd
        self.isBackgroundColorGradient = isBackgroundColorGradient
        self.cornerRadius = cornerRadius
        self.cornerStyle = cornerStyle
        self.imageSingleTapAction = imageSingleTapAction
        self.imageDoubleTapAction = imageDoubleTapAction
    }
    
    // MARK: - Private computed properties:
    
    /// Value of the alignment of the view that is based on the size of the dynamic type that is currently selected:
    private var alignmentValue: NT_Alignment {
        dynamicTypeSize >= .accessibility1 ? .vertical : alignment
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .contentBackground(
                verticalPadding: verticalPadding,
                horizontalPadding: horizontalPadding,
                maxHeight: maxHeight,
                maxHeightAlignment: maxHeightAlignment,
                isShowingBackground: isShowingBackground,
                backgroundColor: backgroundColor,
                backgroundGradientStart: backgroundGradientStart,
                backgroundGradientEnd: backgroundGradientEnd,
                isBackgroundColorGradient: isBackgroundColorGradient,
                cornerRadius: cornerRadius,
                cornerStyle: cornerStyle
            )
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Item:

private extension ImageBackgroundBadgeTitleSubtitleView {
    @ViewBuilder
    private var item: some View {
        switch alignmentValue {
        case .horizontal: horizontalItem
        case .vertical: verticalItem
        }
    }
    
    private var horizontalItem: some View {
        HStack(
            alignment: verticalAlignment,
            spacing: spacing
        ) {
            itemContent
        }
    }
    
    private var verticalItem: some View {
        VStack(
            alignment: horizontalAlignment,
            spacing: spacing
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        if isReversed {
            reversedItemContent
        } else {
            defaultItemContent
        }
    }
    
    @ViewBuilder
    private var reversedItemContent: some View {
        titleSubtitle
        imageContent
    }
    
    @ViewBuilder
    private var defaultItemContent: some View {
        imageContent
        titleSubtitle
    }
}

// MARK: - Image:

private extension ImageBackgroundBadgeTitleSubtitleView {
    private var imageContent: some View {
        ImageBackgroundBadgeView(
            image: image,
            isImageResizable: isImageResizable,
            isImageClipped: isImageClipped,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            isImageFullWidth: isImageFullWidth,
            isShowingImageBackground: isShowingImageBackground,
            imageBackgroundColor: imageBackgroundColor,
            imageBackgroundGradientStart: imageBackgroundGradientStart,
            imageBackgroundGradientEnd: imageBackgroundGradientEnd,
            isImageBackgroundColorGradient: isImageBackgroundColorGradient,
            imageCornerRadius: imageCornerRadius,
            imageCornerStyle: imageCornerStyle,
            imageBorderWidth: imageBorderWidth,
            imageBorderColor: imageBorderColor,
            isShowingBadge: isShowingBadge,
            isShowingBadgeIcon: isShowingBadgeIcon,
            badgeIcon: badgeIcon,
            badgeIconSymbolVariant: badgeIconSymbolVariant,
            badgeIconColor: badgeIconColor,
            badgeIconGradientStart: badgeIconGradientStart,
            badgeIconGradientEnd: badgeIconGradientEnd,
            isBadgeIconColorGradient: isBadgeIconColorGradient,
            badgeTitle: badgeTitle,
            isBadgeTitleLocalized: isBadgeTitleLocalized,
            badgeTitleTextCase: badgeTitleTextCase,
            badgeTitleAlignment: badgeTitleAlignment,
            badgeTitleColor: badgeTitleColor,
            badgeTitleGradientStart: badgeTitleGradientStart,
            badgeTitleGradientEnd: badgeTitleGradientEnd,
            isBadgeTitleColorGradient: isBadgeTitleColorGradient,
            badgeBackgroundColor: badgeBackgroundColor,
            badgeBackgroundGradientStart: badgeBackgroundGradientStart,
            badgeBackgroundGradientEnd: badgeBackgroundGradientEnd,
            isBadgeBackgroundColorGradient: isBadgeBackgroundColorGradient,
            isShowingBadgeBorder: isShowingBadgeBorder,
            badgeBorderColor: badgeBorderColor,
            badgeSize: badgeSize,
            badgeAlignment: badgeAlignment,
            badgeVerticalPadding: badgeVerticalPadding,
            badgeHorizontalPadding: badgeHorizontalPadding,
            badgeXAxisOffset: badgeXAxisOffset,
            badgeYAxisOffset: badgeYAxisOffset,
            imageSingleTapAction: imageSingleTapAction,
            imageDoubleTapAction: imageDoubleTapAction
        )
    }
}

// MARK: - Title and subtitle:

private extension ImageBackgroundBadgeTitleSubtitleView {
    private var titleSubtitle: some View {
        TitleSubtitleView(
            isShowingTitle: isShowingTitle,
            title: title,
            isTitleLocalized: isTitleLocalized,
            titleFont: titleFont,
            titleTextCase: titleTextCase,
            titleAlignment: titleAlignment,
            titleLineSpacing: titleLineSpacing,
            titleLineLimit: titleLineLimit,
            titleColor: titleColor,
            isShowingSubtitle: isShowingSubtitle,
            subtitle: subtitle,
            isSubtitleLocalized: isSubtitleLocalized,
            subtitleFont: subtitleFont,
            subtitleTextCase: subtitleTextCase,
            subtitleAlignment: subtitleAlignment,
            subtitleLineSpacing: subtitleLineSpacing,
            subtitleLineLimit: subtitleLineLimit,
            subtitleColor: subtitleColor,
            alignment: titleSubtitleAlignment,
            spacing: titleSubtitleSpacing,
            maxWidth: titleSubtitleMaxWidth,
            maxWidthAlignment: titleSubtitleMaxWidthAlignment,
            verticalPadding: titleSubtitleVerticalPadding,
            horizontalPadding: titleSubtitleHorizontalPadding
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        ImageBackgroundBadgeTitleSubtitleView(
            image: .init(.productDetails5),
            isImageResizable: true,
            isImageClipped: true,
            imageWidth: 304,
            imageHeight: 168,
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
            badgeYAxisOffset: 8,
            title: "Title",
            isTitleLocalized: true,
            titleFont: .headline,
            titleTextCase: .none,
            titleAlignment: .leading,
            titleLineSpacing: 0,
            titleLineLimit: nil,
            titleColor: .primary,
            isShowingSubtitle: true,
            subtitle: "Subtitle",
            isSubtitleLocalized: true,
            subtitleFont: .subheadline,
            subtitleTextCase: .none,
            subtitleAlignment: .leading,
            subtitleLineSpacing: 0,
            subtitleLineLimit: nil,
            subtitleColor: .secondary,
            titleSubtitleAlignment: .leading,
            titleSubtitleSpacing: 4,
            titleSubtitleMaxWidth: nil,
            titleSubtitleMaxWidthAlignment: .leading,
            titleSubtitleVerticalPadding: 0,
            titleSubtitleHorizontalPadding: 0,
            isReversed: false,
            alignment: .vertical,
            verticalAlignment: .top,
            horizontalAlignment: .leading,
            spacing: 12,
            verticalPadding: 12,
            horizontalPadding: 12,
            maxHeight: nil,
            maxHeightAlignment: .topLeading,
            isShowingBackground: true,
            backgroundColor: .init(.secondarySystemGroupedBackground),
            backgroundGradientStart: .blueGradientStart,
            backgroundGradientEnd: .blueGradientEnd,
            isBackgroundColorGradient: false,
            cornerRadius: 16,
            cornerStyle: .continuous
        ) {
            
        } imageDoubleTapAction: {
            
        }
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .background(Color(.systemGroupedBackground))
}
