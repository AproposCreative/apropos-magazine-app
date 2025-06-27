//
//  ImageBackgroundTitleSubtitleBadgeView.swift
//  Native
//

import SwiftUI

struct ImageBackgroundTitleSubtitleBadgeView: View {
    
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
    
    /// Alignment of the title and the subtitle if they have a maximum width applied to them:
    private let titleSubtitleMaxWidthAlignment: Alignment
    
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
    
    /// Color of the background of the badge:
    private let badgeBackgroundColor: Color
    
    /// Starting color of the gradient of the background of the badge if applicable:
    private let badgeBackgroundGradientStart: Color
    
    /// Ending color of the gradient of the background of the badge if applicable:
    private let badgeBackgroundGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the background color of the badge should have a gradient applied to it:
    private let isBadgeBackgroundColorGradient: Bool
    
    /// 'Bool' value indicating whether or not the border of the badge should be shown at all:
    private let isShowingBadgeBorder: Bool
    
    /// Color of the border of the badge:
    private let badgeBorderColor: Color
    
    /// Size of the badge:
    private let badgeSize: NT_BadgeSize
    
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
        imageWidth: CGFloat? = 48,
        imageHeight: CGFloat? = 48,
        imageMaxWidth: CGFloat? = nil,
        imageAlignment: Alignment = .center,
        isImageFullWidth: Bool = false,
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
        titleSubtitleMaxWidth: CGFloat? = .infinity,
        titleSubtitleMaxWidthAlignment: Alignment = .leading,
        isShowingBadge: Bool = true,
        badgeTitle: String,
        isBadgeTitleLocalized: Bool = true,
        badgeTitleTextCase: Text.Case? = .uppercase,
        badgeTitleAlignment: TextAlignment = .center,
        badgeTitleColor: Color = .white,
        badgeBackgroundColor: Color = .accent,
        badgeBackgroundGradientStart: Color = .blueGradientStart,
        badgeBackgroundGradientEnd: Color = .blueGradientEnd,
        isBadgeBackgroundColorGradient: Bool = true,
        isShowingBadgeBorder: Bool = false,
        badgeBorderColor: Color = .init(.secondarySystemGroupedBackground),
        badgeSize: NT_BadgeSize = .small,
        alignment: NT_Alignment = .horizontal,
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

private extension ImageBackgroundTitleSubtitleBadgeView {
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
            horizontalItemContent
        }
    }
    
    private var verticalItem: some View {
        VStack(
            alignment: horizontalAlignment,
            spacing: spacing
        ) {
            verticalItemContent
        }
    }
    
    @ViewBuilder
    private var horizontalItemContent: some View {
        imageContent
        titleSubtitle
        badge
    }
    
    @ViewBuilder
    private var verticalItemContent: some View {
        verticalHeader
        titleSubtitle
    }
    
    private var verticalHeader: some View {
        HStack(
            alignment: verticalAlignment,
            spacing: spacing
        ) {
            verticalHeaderContent
        }
    }
    
    @ViewBuilder
    private var verticalHeaderContent: some View {
        imageContent
        verticalHeaderBadge
    }
    
    private var verticalHeaderBadge: some View {
        badge
            .frame(
                maxWidth: .infinity,
                alignment: .trailing
            )
    }
}

// MARK: - Image:

private extension ImageBackgroundTitleSubtitleBadgeView {
    private var imageContent: some View {
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

// MARK: - Title and subtitle:

private extension ImageBackgroundTitleSubtitleBadgeView {
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
            maxWidthAlignment: titleSubtitleMaxWidthAlignment
        )
    }
}

// MARK: - Badge:

private extension ImageBackgroundTitleSubtitleBadgeView {
    @ViewBuilder
    private var badge: some View {
        if isShowingBadge {
            badgeContent
        }
    }
    
    private var badgeContent: some View {
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
    ScrollView {
        ImageBackgroundTitleSubtitleBadgeView(
            image: .init(.profile1),
            isImageResizable: true,
            isImageClipped: true,
            imageWidth: 48,
            imageHeight: 48,
            imageMaxWidth: nil,
            imageAlignment: .center,
            isImageFullWidth: false,
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
            isShowingTitle: true,
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
            titleSubtitleMaxWidth: .infinity,
            titleSubtitleMaxWidthAlignment: .leading,
            isShowingBadge: true,
            badgeTitle: "Title",
            isBadgeTitleLocalized: true,
            badgeTitleTextCase: .uppercase,
            badgeTitleAlignment: .center,
            badgeTitleColor: .white,
            badgeBackgroundColor: .accent,
            badgeBackgroundGradientStart: .blueGradientStart,
            badgeBackgroundGradientEnd: .blueGradientEnd,
            isBadgeBackgroundColorGradient: true,
            isShowingBadgeBorder: false,
            badgeBorderColor: .init(.secondarySystemGroupedBackground),
            badgeSize: .small,
            alignment: .horizontal,
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
