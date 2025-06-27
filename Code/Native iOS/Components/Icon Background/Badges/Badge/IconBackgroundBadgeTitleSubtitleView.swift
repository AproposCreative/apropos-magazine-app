//
//  IconBackgroundBadgeTitleSubtitleView.swift
//  Native
//

import SwiftUI

struct IconBackgroundBadgeTitleSubtitleView: View {
    
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
    
    /// 'Bool' value indicating whether or not the title should be shown:
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
    
    /// 'Bool' value indicating whether or not the subtitle should be shown:
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
    
    /// Vertical padding around the title and the subtitle:
    private let titleSubtitleVerticalPadding: Double
    
    /// Horizontal padding around the title and the subtitle:
    private let titleSubtitleHorizontalPadding: Double
    
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
    
    /// Alignment of the frame of the view:
    private let frameAlignment: Alignment
    
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
        badgeAlignment: Alignment = .topTrailing,
        isShowingTitle: Bool = true,
        title: String,
        isTitleLocalized: Bool = true,
        titleFont: Font = .title2.bold(),
        titleTextCase: Text.Case? = .none,
        titleAlignment: TextAlignment = .center,
        titleLineSpacing: Double = 0,
        titleLineLimit: Int? = nil,
        titleColor: Color = .primary,
        isShowingSubtitle: Bool = true,
        subtitle: String,
        isSubtitleLocalized: Bool = true,
        subtitleFont: Font = .body,
        subtitleTextCase: Text.Case? = .none,
        subtitleAlignment: TextAlignment = .center,
        subtitleLineSpacing: Double = 0,
        subtitleLineLimit: Int? = nil,
        subtitleColor: Color = .secondary,
        titleSubtitleAlignment: HorizontalAlignment = .center,
        titleSubtitleSpacing: Double = 12,
        titleSubtitleMaxWidth: CGFloat? = nil,
        titleSubtitleVerticalPadding: Double = 0,
        titleSubtitleHorizontalPadding: Double = 0,
        alignment: NT_Alignment = .vertical,
        verticalAlignment: VerticalAlignment = .top,
        horizontalAlignment: HorizontalAlignment = .center,
        spacing: Double = 48,
        verticalPadding: Double = 0,
        horizontalPadding: Double = 0,
        frameAlignment: Alignment = .center
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
        self.titleSubtitleVerticalPadding = titleSubtitleVerticalPadding
        self.titleSubtitleHorizontalPadding = titleSubtitleHorizontalPadding
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
        self.horizontalAlignment = horizontalAlignment
        self.spacing = spacing
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
        self.frameAlignment = frameAlignment
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
            .padding(
                .vertical,
                verticalPadding
            )
            .padding(
                .horizontal,
                horizontalPadding
            )
            .frame(
                maxWidth: .infinity,
                alignment: frameAlignment
            )
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Item:

private extension IconBackgroundBadgeTitleSubtitleView {
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
        iconBadge
        titleSubtitle
    }
}

// MARK: - Icon and badge:

private extension IconBackgroundBadgeTitleSubtitleView {
    private var iconBadge: some View {
        IconBackgroundBadgeView(
            icon: icon,
            iconSymbolVariant: iconSymbolVariant,
            iconColor: iconColor,
            iconGradientStart: iconGradientStart,
            iconGradientEnd: iconGradientEnd,
            isIconColorGradient: isIconColorGradient,
            isShowingIconBackground: isShowingIconBackground,
            iconBackgroundColor: iconBackgroundColor,
            iconBackgroundGradientStart: iconBackgroundGradientStart,
            iconBackgroundGradientEnd: iconBackgroundGradientEnd,
            isIconBackgroundColorGradient: isIconBackgroundColorGradient,
            iconSize: iconSize,
            isShowingBadge: isShowingBadge,
            badgeTitle: badgeTitle,
            isBadgeTitleLocalized: isBadgeTitleLocalized,
            badgeTitleTextCase: badgeTitleTextCase,
            badgeTitleAlignment: badgeTitleAlignment,
            badgeTitleColor: badgeTitleColor,
            badgeBackgroundColor: badgeBackgroundColor,
            badgeBackgroundGradientStart: badgeBackgroundGradientStart,
            badgeBackgroundGradientEnd: badgeBackgroundGradientEnd,
            isBadgeBackgroundColorGradient: isBadgeBackgroundColorGradient,
            isShowingBadgeBorder: isShowingBadgeBorder,
            badgeBorderColor: badgeBorderColor,
            badgeSize: badgeSize,
            badgeXAxisOffset: badgeXAxisOffset,
            badgeYAxisOffset: badgeYAxisOffset,
            badgeAlignment: badgeAlignment
        )
    }
}

// MARK: - Title and subtitle:

private extension IconBackgroundBadgeTitleSubtitleView {
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
            verticalPadding: titleSubtitleVerticalPadding,
            horizontalPadding: titleSubtitleHorizontalPadding
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        IconBackgroundBadgeTitleSubtitleView(
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
            iconSize: .twoHundredPixels,
            isShowingBadge: true,
            badgeTitle: "Title",
            isBadgeTitleLocalized: true,
            badgeTitleTextCase: .uppercase,
            badgeTitleAlignment: .center,
            badgeTitleColor: .white,
            badgeBackgroundColor: .blue,
            badgeBackgroundGradientStart: .blueGradientStart,
            badgeBackgroundGradientEnd: .blueGradientEnd,
            isShowingBadgeBorder: true,
            badgeBorderColor: .init(.systemBackground),
            badgeSize: .large,
            badgeXAxisOffset: 24,
            badgeYAxisOffset: 12,
            badgeAlignment: .topTrailing,
            isShowingTitle: true,
            title: "Title",
            isTitleLocalized: true,
            titleFont: .title2.bold(),
            titleTextCase: .none,
            titleAlignment: .center,
            titleLineSpacing: 0,
            titleLineLimit: nil,
            titleColor: .primary,
            isShowingSubtitle: true,
            subtitle: "Subtitle",
            isSubtitleLocalized: true,
            subtitleFont: .body,
            subtitleTextCase: .none,
            subtitleAlignment: .center,
            subtitleLineSpacing: 0,
            subtitleLineLimit: nil,
            subtitleColor: .secondary,
            titleSubtitleAlignment: .center,
            titleSubtitleSpacing: 12,
            titleSubtitleMaxWidth: nil,
            titleSubtitleVerticalPadding: 0,
            titleSubtitleHorizontalPadding: 0,
            alignment: .vertical,
            verticalAlignment: .top,
            horizontalAlignment: .center,
            spacing: 48,
            verticalPadding: 16,
            horizontalPadding: 16,
            frameAlignment: .center
        )
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
