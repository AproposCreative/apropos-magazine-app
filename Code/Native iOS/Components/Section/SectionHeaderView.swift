//
//  SectionHeaderView.swift
//  Native
//

import SwiftUI

struct SectionHeaderView: View {
    
    // MARK: - Private properties:
    
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
    private let titleColor: Color?
    
    /// Starting color of the gradient of the title if applicable:
    private let titleGradientStart: Color
    
    /// Ending color of the gradient of the title if applicable:
    private let titleGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the title should have a gradient applied to it:
    private let isTitleColorGradient: Bool
    
    /// Maximum width that the title should have if applicable:
    private let titleMaxWidth: CGFloat?
    
    /// Alignment of the title if it has a maximum width applied to it:
    private let titleMaxWidthAlignment: Alignment
    
    /// 'Bool' value indicating whether or not the icon should be shown at all:
    private let isShowingIcon: Bool
    
    /// An actual icon to display if applicable:
    private let icon: String
    
    /// Symbol variant of the icon if applicable (It could be '.fill', '.circle', etc.):
    private let iconSymbolVariant: SymbolVariants
    
    /// Font of the icon if applicable:
    private let iconFont: Font
    
    /// Color of the icon if applicable:
    private let iconColor: Color
    
    /// Starting color of the gradient of the icon if applicable:
    private let iconGradientStart: Color
    
    /// Ending color of the gradient of the icon if applicable:
    private let iconGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the icon should have a gradient applied to it if applicable:
    private let isIconColorGradient: Bool
    
    /// Size of the frame of the icon if applicable:
    private let iconFrame: CGFloat?
    
    /// Alignment of the title and the icon:
    private let titleIconAlignment: VerticalAlignment
    
    /// Spacing between the title and the icon:
    private let titleIconSpacing: Double
    
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
    private let subtitleColor: Color?
    
    /// Starting color of the gradient of the subtitle if applicable:
    private let subtitleGradientStart: Color
    
    /// Ending color of the gradient of the subtitle if applicable:
    private let subtitleGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the subtitle should have a gradient applied to it:
    private let isSubtitleColorGradient: Bool
    
    /// Alignment of the content of the view:
    private let alignment: HorizontalAlignment
    
    /// Spacing between the content of the view:
    private let spacing: Double
    
    /// Vertical padding of the view:
    private let verticalPadding: Double
    
    /// Horizontal padding of the view:
    private let horizontalPadding: Double
    
    init(
        title: String,
        isTitleLocalized: Bool = true,
        titleFont: Font = .title3.bold(),
        titleTextCase: Text.Case? = .none,
        titleAlignment: TextAlignment = .leading,
        titleLineSpacing: Double = 0,
        titleColor: Color? = .primary,
        titleGradientStart: Color = .blueGradientStart,
        titleGradientEnd: Color = .blueGradientEnd,
        isTitleColorGradient: Bool = false,
        titleMaxWidth: CGFloat? = .infinity,
        titleMaxWidthAlignment: Alignment = .leading,
        isShowingIcon: Bool = false,
        icon: String = Icons.chevronRight,
        iconSymbolVariant: SymbolVariants = .fill,
        iconFont: Font = .headline,
        iconColor: Color = .init(.tertiaryLabel),
        iconGradientStart: Color = .blueGradientStart,
        iconGradientEnd: Color = .blueGradientEnd,
        isIconColorGradient: Bool = false,
        iconFrame: CGFloat? = 25,
        titleIconAlignment: VerticalAlignment = .center,
        titleIconSpacing: Double = 2,
        isShowingSubtitle: Bool = false,
        subtitle: String = "",
        isSubtitleLocalized: Bool = true,
        subtitleFont: Font = .body,
        subtitleTextCase: Text.Case? = .none,
        subtitleAlignment: TextAlignment = .leading,
        subtitleLineSpacing: Double = 0,
        subtitleColor: Color? = .secondary,
        subtitleGradientStart: Color = .blueGradientStart,
        subtitleGradientEnd: Color = .blueGradientEnd,
        isSubtitleColorGradient: Bool = false,
        alignment: HorizontalAlignment = .leading,
        spacing: Double = 6,
        verticalPadding: Double = 0,
        horizontalPadding: Double = 0
    ) {
        
        /// Properties initialization:
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
        self.isShowingIcon = isShowingIcon
        self.icon = icon
        self.iconSymbolVariant = iconSymbolVariant
        self.iconFont = iconFont
        self.iconColor = iconColor
        self.iconGradientStart = iconGradientStart
        self.iconGradientEnd = iconGradientEnd
        self.isIconColorGradient = isIconColorGradient
        self.iconFrame = iconFrame
        self.titleIconAlignment = titleIconAlignment
        self.titleIconSpacing = titleIconSpacing
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
        self.alignment = alignment
        self.spacing = spacing
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
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
            .accessibilityAddTraits(.isHeader)
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Item:

private extension SectionHeaderView {
    private var item: some View {
        VStack(
            alignment: alignment,
            spacing: spacing
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        titleIcon
        subtitleContent
    }
}

// MARK: - Title and icon:

private extension SectionHeaderView {
    private var titleIcon: some View {
        HStack(
            alignment: titleIconAlignment,
            spacing: titleIconSpacing
        ) {
            titleIconContent
        }
    }
    
    @ViewBuilder
    private var titleIconContent: some View {
        titleContent
        iconContent
    }
}

// MARK: - Title:

private extension SectionHeaderView {
    private var titleContent: some View {
        titleItem
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
    private var titleItem: some View {
        if isTitleLocalized {
            Text(.init(title))
        } else {
            Text(title)
        }
    }
}

// MARK: - Icon:

private extension SectionHeaderView {
    @ViewBuilder
    private var iconContent: some View {
        if isShowingIcon {
            iconItem
        }
    }
    
    private var iconItem: some View {
        Image(systemName: icon)
            .symbolVariant(iconSymbolVariant)
            .font(iconFont)
            .foregroundGradient(
                color: iconColor,
                gradientStart: iconGradientStart,
                gradientEnd: iconGradientEnd,
                isGradient: isIconColorGradient
            )
            .frame(
                width: iconFrame,
                height: iconFrame,
                alignment: .center
            )
    }
}

// MARK: - Subtitle:

private extension SectionHeaderView {
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
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            SectionHeaderView(
                title: "Title",
                isTitleLocalized: true,
                titleFont: .title3.bold(),
                titleTextCase: .none,
                titleAlignment: .leading,
                titleLineSpacing: 0,
                titleColor: .primary,
                titleGradientStart: .blueGradientStart,
                titleGradientEnd: .blueGradientEnd,
                isTitleColorGradient: false,
                titleMaxWidth: .infinity,
                titleMaxWidthAlignment: .leading,
                isShowingIcon: false,
                icon: Icons.chevronRight,
                iconSymbolVariant: .fill,
                iconFont: .headline,
                iconColor: .init(.tertiaryLabel),
                iconGradientStart: .blueGradientStart,
                iconGradientEnd: .blueGradientEnd,
                isIconColorGradient: false,
                iconFrame: 25,
                titleIconAlignment: .center,
                titleIconSpacing: 2,
                isShowingSubtitle: false,
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
                alignment: .leading,
                spacing: 6,
                verticalPadding: 0,
                horizontalPadding: 0
            )
            
            IconBackgroundTitleSubtitleView(
                icon: Icons.mailStack,
                title: "Title",
                subtitle: "Subtitle"
            )
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
