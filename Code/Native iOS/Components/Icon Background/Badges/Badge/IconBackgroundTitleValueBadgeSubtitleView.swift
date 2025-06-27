//
//  IconBackgroundTitleValueBadgeSubtitleView.swift
//  Native
//

import SwiftUI

struct IconBackgroundTitleValueBadgeSubtitleView: View {
    
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
    
    /// 'Bool' value indicating whether or not the icon should take the full width:
    private let isIconFullWidth: Bool
    
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
    
    /// Width of the border of the icon:
    private let iconBorderWidth: Double
    
    /// Color of the border of the icon:
    private let iconBorderColor: Color
    
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
    
    /// Color of the title:
    private let titleColor: Color
    
    /// Starting color of the gradient of the title if applicable:
    private let titleGradientStart: Color
    
    /// Ending color of the gradient of the title if applicable:
    private let titleGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the title should have a gradient applied to it:
    private let isTitleColorGradient: Bool
    
    /// Maximum width of the title:
    private let titleMaxWidth: CGFloat?
    
    /// Alignment of the title if it has a maximum width applied to it:
    private let titleMaxWidthAlignment: Alignment
    
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
    
    /// Alignment of the title and the badge:
    private let titleBadgeAlignment: VerticalAlignment
    
    /// Spacing between the title and the badge:
    private let titleBadgeSpacing: Double
    
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
    
    /// Color of the subtitle:
    private let subtitleColor: Color
    
    /// Starting color of the gradient of the subtitle if applicable:
    private let subtitleGradientStart: Color
    
    /// Ending color of the gradient of the subtitle if applicable:
    private let subtitleGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the subtitle should have a gradient applied to it:
    private let isSubtitleColorGradient: Bool
    
    /// Alignment of the title, badge, and the subtitle:
    private let titleBadgeSubtitleAlignment: HorizontalAlignment
    
    /// Spacing between the title, badge, and the subtitle:
    private let titleBadgeSubtitleSpacing: Double
    
    /// Maximum width of the title, badge, and the subtitle:
    private let titleBadgeSubtitleMaxWidth: CGFloat?
    
    /// Alignment of the title, badge, and the subtitle if they have a maximum width applied to them:
    private let titleBadgeSubtitleMaxWidthAlignment: Alignment
    
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
    
    /// Action of the icon after single tapping on it if applicable:
    private let iconSingleTapAction: (() -> ())?
    
    /// Action of the icon after double tapping on it if applicable:
    private let iconDoubleTapAction: (() -> ())?
    
    init(
        icon: String,
        iconSymbolVariant: SymbolVariants = .fill,
        iconColor: Color = .white,
        iconGradientStart: Color = .blueGradientStart,
        iconGradientEnd: Color = .blueGradientEnd,
        isIconColorGradient: Bool = false,
        isShowingIconBackground: Bool = true,
        isIconFullWidth: Bool = false,
        iconBackgroundColor: Color = .accent,
        iconBackgroundGradientStart: Color = .blueGradientStart,
        iconBackgroundGradientEnd: Color = .blueGradientEnd,
        isIconBackgroundColorGradient: Bool = true,
        iconSize: NT_IconSize = .fortyEightPixels,
        iconBorderWidth: Double = 0,
        iconBorderColor: Color = .accent,
        isShowingTitle: Bool = true,
        title: String,
        isTitleLocalized: Bool = true,
        titleFont: Font = .title2.bold(),
        titleTextCase: Text.Case? = .none,
        titleAlignment: TextAlignment = .leading,
        titleLineSpacing: Double = 0,
        titleColor: Color = .primary,
        titleGradientStart: Color = .blueGradientStart,
        titleGradientEnd: Color = .blueGradientEnd,
        isTitleColorGradient: Bool = false,
        titleMaxWidth: CGFloat? = .infinity,
        titleMaxWidthAlignment: Alignment = .leading,
        isShowingBadge: Bool = true,
        isShowingBadgeIcon: Bool = true,
        badgeIcon: String,
        badgeIconSymbolVariant: SymbolVariants = .fill,
        badgeIconColor: Color = .accent,
        badgeIconGradientStart: Color = .blueGradientStart,
        badgeIconGradientEnd: Color = .blueGradientEnd,
        isBadgeIconColorGradient: Bool = true,
        badgeTitle: String,
        isBadgeTitleLocalized: Bool = true,
        badgeTitleTextCase: Text.Case? = .none,
        badgeTitleAlignment: TextAlignment = .leading,
        badgeTitleColor: Color = .primary,
        badgeTitleGradientStart: Color = .blueGradientStart,
        badgeTitleGradientEnd: Color = .blueGradientEnd,
        isBadgeTitleColorGradient: Bool = false,
        badgeBackgroundColor: Color = .init(.systemGroupedBackground),
        badgeBackgroundGradientStart: Color = .blueGradientStart,
        badgeBackgroundGradientEnd: Color = .blueGradientEnd,
        isBadgeBackgroundColorGradient: Bool = false,
        isShowingBadgeBorder: Bool = false,
        badgeBorderColor: Color = .init(.secondarySystemGroupedBackground),
        badgeSize: NT_BadgeSize = .extraSmall,
        titleBadgeAlignment: VerticalAlignment = .top,
        titleBadgeSpacing: Double = 12,
        isShowingSubtitle: Bool = true,
        subtitle: String,
        isSubtitleLocalized: Bool = true,
        subtitleFont: Font = .body,
        subtitleTextCase: Text.Case? = .none,
        subtitleAlignment: TextAlignment = .leading,
        subtitleLineSpacing: Double = 0,
        subtitleColor: Color = .secondary,
        subtitleGradientStart: Color = .blueGradientStart,
        subtitleGradientEnd: Color = .blueGradientEnd,
        isSubtitleColorGradient: Bool = false,
        titleBadgeSubtitleAlignment: HorizontalAlignment = .leading,
        titleBadgeSubtitleSpacing: Double = 6,
        titleBadgeSubtitleMaxWidth: CGFloat? = .infinity,
        titleBadgeSubtitleMaxWidthAlignment: Alignment = .leading,
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
        iconSingleTapAction: (() -> ())? = nil,
        iconDoubleTapAction: (() -> ())? = nil
    ) {
        
        /// Properties initialization:
        self.icon = icon
        self.iconSymbolVariant = iconSymbolVariant
        self.iconColor = iconColor
        self.iconGradientStart = iconGradientStart
        self.iconGradientEnd = iconGradientEnd
        self.isIconColorGradient = isIconColorGradient
        self.isShowingIconBackground = isShowingIconBackground
        self.isIconFullWidth = isIconFullWidth
        self.iconBackgroundColor = iconBackgroundColor
        self.iconBackgroundGradientStart = iconBackgroundGradientStart
        self.iconBackgroundGradientEnd = iconBackgroundGradientEnd
        self.isIconBackgroundColorGradient = isIconBackgroundColorGradient
        self.iconSize = iconSize
        self.iconBorderWidth = iconBorderWidth
        self.iconBorderColor = iconBorderColor
        self.isShowingTitle = isShowingTitle
        self.title = title
        self.isTitleLocalized = isTitleLocalized
        self.titleFont = titleFont
        self.titleTextCase = titleTextCase
        self.titleAlignment = titleAlignment
        self.titleLineSpacing = titleLineSpacing
        self.titleColor = titleColor
        self.titleGradientStart = titleGradientStart
        self.titleGradientEnd = titleGradientEnd
        self.isTitleColorGradient = isTitleColorGradient
        self.titleMaxWidth = titleMaxWidth
        self.titleMaxWidthAlignment = titleMaxWidthAlignment
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
        self.titleBadgeAlignment = titleBadgeAlignment
        self.titleBadgeSpacing = titleBadgeSpacing
        self.isShowingSubtitle = isShowingSubtitle
        self.subtitle = subtitle
        self.isSubtitleLocalized = isSubtitleLocalized
        self.subtitleFont = subtitleFont
        self.subtitleTextCase = subtitleTextCase
        self.subtitleAlignment = subtitleAlignment
        self.subtitleLineSpacing = subtitleLineSpacing
        self.subtitleColor = subtitleColor
        self.subtitleGradientStart = subtitleGradientStart
        self.subtitleGradientEnd = subtitleGradientEnd
        self.isSubtitleColorGradient = isSubtitleColorGradient
        self.titleBadgeSubtitleAlignment = titleBadgeSubtitleAlignment
        self.titleBadgeSubtitleSpacing = titleBadgeSubtitleSpacing
        self.titleBadgeSubtitleMaxWidth = titleBadgeSubtitleMaxWidth
        self.titleBadgeSubtitleMaxWidthAlignment = titleBadgeSubtitleMaxWidthAlignment
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
        self.iconSingleTapAction = iconSingleTapAction
        self.iconDoubleTapAction = iconDoubleTapAction
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

private extension IconBackgroundTitleValueBadgeSubtitleView {
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
    
    @ViewBuilder
    private var horizontalItemContent: some View {
        iconContent
        titleBadgeSubtitle
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
    private var verticalItemContent: some View {
        verticalItemHeader
        verticalItemTitleSubtitle
    }
    
    private var verticalItemHeader: some View {
        HStack(
            alignment: titleBadgeAlignment,
            spacing: titleBadgeSpacing
        ) {
            verticalItemHeaderContent
        }
    }
    
    @ViewBuilder
    private var verticalItemHeaderContent: some View {
        iconContent
        verticalItemHeaderBadge
    }
    
    private var verticalItemHeaderBadge: some View {
        badge
            .frame(
                maxWidth: .infinity,
                alignment: .trailing
            )
    }
    
    private var verticalItemTitleSubtitle: some View {
        VStack(
            alignment: titleBadgeSubtitleAlignment,
            spacing: titleBadgeSubtitleSpacing
        ) {
            verticalItemTitleSubtitleContent
        }
    }
    
    @ViewBuilder
    private var verticalItemTitleSubtitleContent: some View {
        titleContent
        subtitleContent
    }
}

// MARK: - Icon:

private extension IconBackgroundTitleValueBadgeSubtitleView {
    private var iconContent: some View {
        IconBackgroundView(
            icon: icon,
            symbolVariant: iconSymbolVariant,
            color: iconColor,
            gradientStart: iconGradientStart,
            gradientEnd: iconGradientEnd,
            isColorGradient: isIconColorGradient,
            isShowingBackground: isShowingIconBackground,
            isFullWidth: isIconFullWidth,
            backgroundColor: iconBackgroundColor,
            backgroundGradientStart: iconBackgroundGradientStart,
            backgroundGradientEnd: iconBackgroundGradientEnd,
            isBackgroundColorGradient: isIconBackgroundColorGradient,
            size: iconSize,
            borderWidth: iconBorderWidth,
            borderColor: iconBorderColor,
            singleTapAction: iconSingleTapAction,
            doubleTapAction: iconDoubleTapAction
        )
    }
}

// MARK: - Title, badge, and subtitle:

private extension IconBackgroundTitleValueBadgeSubtitleView {
    private var titleBadgeSubtitle: some View {
        titleBadgeSubtitleContent
            .frame(
                maxWidth: titleBadgeSubtitleMaxWidth,
                alignment: titleBadgeSubtitleMaxWidthAlignment
            )
    }
    
    private var titleBadgeSubtitleContent: some View {
        VStack(
            alignment: titleBadgeSubtitleAlignment,
            spacing: titleBadgeSubtitleSpacing
        ) {
            titleBadgeSubtitleItem
        }
    }
    
    @ViewBuilder
    private var titleBadgeSubtitleItem: some View {
        titleBadge
        subtitleContent
    }
    
    private var titleBadge: some View {
        HStack(
            alignment: titleBadgeAlignment,
            spacing: titleBadgeSpacing
        ) {
            titleBadgeContent
        }
    }
    
    @ViewBuilder
    private var titleBadgeContent: some View {
        titleContent
        badge
    }
}

// MARK: - Title:

private extension IconBackgroundTitleValueBadgeSubtitleView {
    @ViewBuilder
    private var titleContent: some View {
        if isShowingTitle {
            titleItem
        }
    }
    
    private var titleItem: some View {
        titleItemContent
            .font(titleFont)
            .textCase(titleTextCase)
            .multilineTextAlignment(titleAlignment)
            .lineSpacing(titleLineSpacing)
            .foregroundGradient(
                color: titleColor,
                gradientStart: titleGradientStart,
                gradientEnd: titleGradientEnd,
                isGradient: isTitleColorGradient
            )
            .frame(
                maxWidth: titleMaxWidth,
                alignment: titleMaxWidthAlignment
            )
    }
    
    @ViewBuilder
    private var titleItemContent: some View {
        if isTitleLocalized {
            Text(.init(title))
        } else {
            Text(title)
        }
    }
}

// MARK: - Badge:

private extension IconBackgroundTitleValueBadgeSubtitleView {
    @ViewBuilder
    private var badge: some View {
        if isShowingBadge {
            badgeContent
        }
    }
    
    private var badgeContent: some View {
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

// MARK: - Subtitle:

private extension IconBackgroundTitleValueBadgeSubtitleView {
    @ViewBuilder
    private var subtitleContent: some View {
        if isShowingSubtitle {
            subtitleItem
        }
    }
    
    private var subtitleItem: some View {
        subtitleItemContent
            .font(subtitleFont)
            .textCase(subtitleTextCase)
            .multilineTextAlignment(subtitleAlignment)
            .lineSpacing(subtitleLineSpacing)
            .foregroundGradient(
                color: subtitleColor,
                gradientStart: subtitleGradientStart,
                gradientEnd: subtitleGradientEnd,
                isGradient: isSubtitleColorGradient
            )
    }
    
    @ViewBuilder
    private var subtitleItemContent: some View {
        if isSubtitleLocalized {
            Text(.init(subtitle))
        } else {
            Text(subtitle)
        }
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        IconBackgroundTitleValueBadgeSubtitleView(
            icon: Icons.mailStack,
            iconSymbolVariant: .fill,
            iconColor: .white,
            iconGradientStart: .blueGradientStart,
            iconGradientEnd: .blueGradientEnd,
            isIconColorGradient: false,
            isShowingIconBackground: true,
            isIconFullWidth: false,
            iconBackgroundColor: .accent,
            iconBackgroundGradientStart: .blueGradientStart,
            iconBackgroundGradientEnd: .blueGradientEnd,
            isIconBackgroundColorGradient: true,
            iconSize: .fortyEightPixels,
            iconBorderWidth: 0,
            iconBorderColor: .accent,
            isShowingTitle: true,
            title: "Title",
            isTitleLocalized: true,
            titleFont: .title2.bold(),
            titleTextCase: .none,
            titleAlignment: .leading,
            titleLineSpacing: 0,
            titleColor: .primary,
            titleGradientStart: .blueGradientStart,
            titleGradientEnd: .blueGradientEnd,
            isTitleColorGradient: false,
            titleMaxWidth: .infinity,
            titleMaxWidthAlignment: .leading,
            isShowingBadge: true,
            isShowingBadgeIcon: true,
            badgeIcon: Icons.mailStack,
            badgeIconSymbolVariant: .fill,
            badgeIconColor: .accent,
            badgeIconGradientStart: .blueGradientStart,
            badgeIconGradientEnd: .blueGradientEnd,
            isBadgeIconColorGradient: true,
            badgeTitle: "Badge",
            isBadgeTitleLocalized: true,
            badgeTitleTextCase: .none,
            badgeTitleAlignment: .leading,
            badgeTitleColor: .primary,
            badgeTitleGradientStart: .blueGradientStart,
            badgeTitleGradientEnd: .blueGradientEnd,
            isBadgeTitleColorGradient: false,
            badgeBackgroundColor: .init(.systemGroupedBackground),
            badgeBackgroundGradientStart: .blueGradientStart,
            badgeBackgroundGradientEnd: .blueGradientEnd,
            isBadgeBackgroundColorGradient: false,
            isShowingBadgeBorder: false,
            badgeBorderColor: .init(.secondarySystemGroupedBackground),
            badgeSize: .extraSmall,
            titleBadgeAlignment: .top,
            titleBadgeSpacing: 12,
            isShowingSubtitle: true,
            subtitle: "Subtitle",
            isSubtitleLocalized: true,
            subtitleFont: .body,
            subtitleTextCase: .none,
            subtitleAlignment: .leading,
            subtitleLineSpacing: 0,
            subtitleColor: .secondary,
            subtitleGradientStart: .blueGradientStart,
            subtitleGradientEnd: .blueGradientEnd,
            isSubtitleColorGradient: false,
            titleBadgeSubtitleAlignment: .leading,
            titleBadgeSubtitleSpacing: 6,
            titleBadgeSubtitleMaxWidth: .infinity,
            titleBadgeSubtitleMaxWidthAlignment: .leading,
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
            
        } iconDoubleTapAction: {
            
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
