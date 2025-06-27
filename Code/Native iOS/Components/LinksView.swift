//
//  LinksView.swift
//  Native
//

import SwiftUI

struct LinksView: View {
    
    // MARK: - Private properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    /// An array of the links to display:
    private let links: [NT_Link]
    
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
    
    /// Alignment of the title and the subtitle:
    private let titleSubtitleAlignment: HorizontalAlignment
    
    /// Spacing between the title and the subtitle:
    private let titleSubtitleSpacing: Double
    
    /// Maximum width of the title and the subtitle:
    private let titleSubtitleMaxWidth: CGFloat?
    
    /// Alignment of the title and the subtitle if they have a maximum width applied to them:
    private let titleSubtitleMaxWidthAlignment: Alignment
    
    /// Symbol variant of the icon (It could be '.fill', '.circle', etc.):
    private let iconSymbolVariant: SymbolVariants
    
    /// Font of the icon:
    private let iconFont: Font
    
    /// Color of the icon:
    private let iconColor: Color
    
    /// Starting color of the gradient of the icon if applicable:
    private let iconGradientStart: Color
    
    /// Ending color of the gradient of the icon if applicable:
    private let iconGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the icon should have a gradient applied to it:
    private let isIconColorGradient: Bool
    
    /// Size of the frame of the icon if applicable:
    private let iconFrame: CGFloat?
    
    /// Alignment of the content of each of the links:
    private let linkAlignment: NT_Alignment
    
    /// Vertical alignment of the content of each of the links:
    private let linkVerticalAlignment: VerticalAlignment
    
    /// Horizontal alignment of the content of each of the links:
    private let linkHorizontalAlignment: HorizontalAlignment
    
    /// Spacing between the content of each of the links:
    private let linkSpacing: Double
    
    /// Vertical padding around the content of each of the links:
    private let linkVerticalPadding: Double
    
    /// Horizontal padding around the content of each of the links:
    private let linkHorizontalPadding: Double
    
    /// 'Bool' value indicating whether or not the background of each of the links should be shown at all:
    private let isShowingLinkBackground: Bool
    
    /// Color of the background of each of the links:
    private let linkBackgroundColor: Color
    
    /// Starting color of the gradient of the background of each of the links if applicable:
    private let linksBackgroundGradientStart: Color
    
    /// Ending color of the gradient of the background of each of the links if applicable:
    private let linksBackgroundGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the background of each of the links should have a gradient applied to it:
    private let isLinksBackgroundColorGradient: Bool
    
    /// Radius of the rounded corners of each of the links:
    private let linkCornerRadius: Double
    
    /// Style of the rounded corners of each of the links:
    private let linkCornerStyle: RoundedCornerStyle
    
    /// 'Bool' value indicating whether or not the divider between the links should be shown at all:
    private let isShowingDivider: Bool
    
    /// Width that the divider should have if applicable:
    private let dividerWidth: CGFloat?
    
    /// Height that the divider should have if applicable:
    private let dividerHeight: CGFloat?
    
    /// Color of the divider:
    private let dividerColor: Color
    
    /// Radius of the rounded corners of the divider:
    private let dividerCornerRadius: Double
    
    /// Style of the rounded corners of the divider:
    private let dividerCornerStyle: RoundedCornerStyle
    
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
    
    init(
        links: [NT_Link],
        titleFont: Font = .headline,
        titleTextCase: Text.Case? = .none,
        titleAlignment: TextAlignment = .leading,
        titleLineSpacing: Double = 0,
        titleColor: Color = .primary,
        subtitleFont: Font = .subheadline,
        subtitleTextCase: Text.Case? = .none,
        subtitleAlignment: TextAlignment = .leading,
        subtitleLineSpacing: Double = 0,
        subtitleColor: Color = .secondary,
        titleSubtitleAlignment: HorizontalAlignment = .leading,
        titleSubtitleSpacing: Double = 4,
        titleSubtitleMaxWidth: CGFloat? = .infinity,
        titleSubtitleMaxWidthAlignment: Alignment = .leading,
        iconSymbolVariant: SymbolVariants = .fill,
        iconFont: Font = .system(
            size: 17,
            weight: .semibold,
            design: .default
        ),
        iconColor: Color = .accent,
        iconGradientStart: Color = .blueGradientStart,
        iconGradientEnd: Color = .blueGradientEnd,
        isIconColorGradient: Bool = true,
        iconFrame: CGFloat? = nil,
        linkAlignment: NT_Alignment = .horizontal,
        linkVerticalAlignment: VerticalAlignment = .top,
        linkHorizontalAlignment: HorizontalAlignment = .leading,
        linkSpacing: Double = 12,
        linkVerticalPadding: Double = 12,
        linkHorizontalPadding: Double = 12,
        isShowingLinkBackground: Bool = true,
        linkBackgroundColor: Color = .init(.secondarySystemGroupedBackground),
        linksBackgroundGradientStart: Color = .blueGradientStart,
        linksBackgroundGradientEnd: Color = .blueGradientEnd,
        isLinksBackgroundColorGradient: Bool = false,
        linkCornerRadius: Double = 16,
        linkCornerStyle: RoundedCornerStyle = .continuous,
        isShowingDivider: Bool = false,
        dividerWidth: CGFloat? = 1,
        dividerHeight: CGFloat? = 20,
        dividerColor: Color = .init(.systemGray),
        dividerCornerRadius: Double = 0.5,
        dividerCornerStyle: RoundedCornerStyle = .continuous,
        alignment: NT_Alignment = .vertical,
        verticalAlignment: VerticalAlignment = .top,
        horizontalAlignment: HorizontalAlignment = .leading,
        spacing: Double = 16,
        verticalPadding: Double = 0,
        horizontalPadding: Double = 0,
        isShowingBackground: Bool = false,
        backgroundColor: Color = .init(.secondarySystemGroupedBackground),
        backgroundGradientStart: Color = .blueGradientStart,
        backgroundGradientEnd: Color = .blueGradientEnd,
        isBackgroundColorGradient: Bool = false,
        cornerRadius: Double = 0,
        cornerStyle: RoundedCornerStyle = .continuous
    ) {
        
        /// Properties initialization:
        self.links = links
        self.titleFont = titleFont
        self.titleTextCase = titleTextCase
        self.titleAlignment = titleAlignment
        self.titleLineSpacing = titleLineSpacing
        self.titleColor = titleColor
        self.subtitleFont = subtitleFont
        self.subtitleTextCase = subtitleTextCase
        self.subtitleAlignment = subtitleAlignment
        self.subtitleLineSpacing = subtitleLineSpacing
        self.subtitleColor = subtitleColor
        self.titleSubtitleAlignment = titleSubtitleAlignment
        self.titleSubtitleSpacing = titleSubtitleSpacing
        self.titleSubtitleMaxWidth = titleSubtitleMaxWidth
        self.titleSubtitleMaxWidthAlignment = titleSubtitleMaxWidthAlignment
        self.iconSymbolVariant = iconSymbolVariant
        self.iconFont = iconFont
        self.iconColor = iconColor
        self.iconGradientStart = iconGradientStart
        self.iconGradientEnd = iconGradientEnd
        self.isIconColorGradient = isIconColorGradient
        self.iconFrame = iconFrame
        self.linkAlignment = linkAlignment
        self.linkVerticalAlignment = linkVerticalAlignment
        self.linkHorizontalAlignment = linkHorizontalAlignment
        self.linkSpacing = linkSpacing
        self.linkVerticalPadding = linkVerticalPadding
        self.linkHorizontalPadding = linkHorizontalPadding
        self.isShowingLinkBackground = isShowingLinkBackground
        self.linkBackgroundColor = linkBackgroundColor
        self.linksBackgroundGradientStart = linksBackgroundGradientStart
        self.linksBackgroundGradientEnd = linksBackgroundGradientEnd
        self.isLinksBackgroundColorGradient = isLinksBackgroundColorGradient
        self.linkCornerRadius = linkCornerRadius
        self.linkCornerStyle = linkCornerStyle
        self.isShowingDivider = isShowingDivider
        self.dividerWidth = dividerWidth
        self.dividerHeight = dividerHeight
        self.dividerColor = dividerColor
        self.dividerCornerRadius = dividerCornerRadius
        self.dividerCornerStyle = dividerCornerStyle
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
        self.horizontalAlignment = horizontalAlignment
        self.spacing = spacing
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
        self.isShowingBackground = isShowingBackground
        self.backgroundColor = backgroundColor
        self.backgroundGradientStart = backgroundGradientStart
        self.backgroundGradientEnd = backgroundGradientEnd
        self.isBackgroundColorGradient = isBackgroundColorGradient
        self.cornerRadius = cornerRadius
        self.cornerStyle = cornerStyle
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    private var isShowing: Bool {
        !links.isEmpty
    }
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    private var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
    
    /// Content of the height of the divider of each of the links that is based on the size of the dynamic type that is currently selected:
    private var dividerHeightContent: CGFloat? {
        shouldMoveContent ? dividerWidth : dividerHeight
    }
    
    /// Value of the alignment of the view that is based on the size of the dynamic type that is currently selected:
    private var alignmentValue: NT_Alignment {
        shouldMoveContent ? .vertical : alignment
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    @ViewBuilder
    private var content: some View {
        if isShowing {
            mainContent
        }
    }
    
    private var mainContent: some View {
        item
            .contentBackground(
                verticalPadding: verticalPadding,
                horizontalPadding: horizontalPadding,
                isShowingBackground: isShowingBackground,
                backgroundColor: backgroundColor,
                backgroundGradientStart: backgroundGradientStart,
                backgroundGradientEnd: backgroundGradientEnd,
                isBackgroundColorGradient: isBackgroundColorGradient,
                cornerRadius: cornerRadius,
                cornerStyle: cornerStyle
            )
    }
}

// MARK: - Item:

private extension LinksView {
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
            linksContent
        }
    }
    
    private var verticalItem: some View {
        VStack(
            alignment: horizontalAlignment,
            spacing: spacing
        ) {
            linksContent
        }
    }
}

// MARK: - Links:

private extension LinksView {
    private var linksContent: some View {
        ForEach(
            links,
            content: link
        )
    }
    
    @ViewBuilder
    private func link(_ link: NT_Link) -> some View {
        linkContent(link)
        linkDivider(link)
    }
    
    private func linkContent(_ link: NT_Link) -> some View {
        linkItem(link)
            .buttonStyle(.plain)
    }
    
    private func linkItem(_ link: NT_Link) -> some View {
        Link(destination: url(link)) {
            linkLabel(link)
        }
    }
    
    private func linkDivider(_ link: NT_Link) -> some View {
        DividerView(
            isShowing: isShowingDivider(link),
            width: dividerWidth,
            height: dividerHeightContent,
            color: dividerColor,
            cornerRadius: dividerCornerRadius,
            cornerStyle: dividerCornerStyle,
            alignment: alignmentValue
        )
    }
    
    private func linkLabel(_ link: NT_Link) -> some View {
        TitleSubtitleIconView(
            isShowingTitle: isShowingTitle(link),
            title: title(link),
            isTitleLocalized: isTitleLocalized(link),
            titleFont: titleFont,
            titleTextCase: titleTextCase,
            titleAlignment: titleAlignment,
            titleLineSpacing: titleLineSpacing,
            titleColor: titleColor,
            isShowingSubtitle: isShowingSubtitle(link),
            subtitle: subtitle(link),
            isSubtitleLocalized: isSubtitleLocalized(link),
            subtitleFont: subtitleFont,
            subtitleTextCase: subtitleTextCase,
            subtitleAlignment: subtitleAlignment,
            subtitleLineSpacing: subtitleLineSpacing,
            subtitleColor: subtitleColor,
            titleSubtitleAlignment: titleSubtitleAlignment,
            titleSubtitleSpacing: titleSubtitleSpacing,
            titleSubtitleMaxWidth: titleSubtitleMaxWidth,
            titleSubtitleMaxWidthAlignment: titleSubtitleMaxWidthAlignment,
            isShowingIcon: isShowingIcon(link),
            icon: icon(link),
            iconSymbolVariant: iconSymbolVariant,
            iconFont: iconFont,
            iconColor: iconColor,
            iconGradientStart: iconGradientStart,
            iconGradientEnd: iconGradientEnd,
            isIconColorGradient: isIconColorGradient,
            iconFrame: iconFrame,
            alignment: linkAlignment,
            verticalAlignment: linkVerticalAlignment,
            horizontalAlignment: linkHorizontalAlignment,
            spacing: linkSpacing,
            verticalPadding: linkVerticalPadding,
            horizontalPadding: linkHorizontalPadding,
            isShowingBackground: isShowingLinkBackground,
            backgroundColor: linkBackgroundColor,
            backgroundGradientStart: linksBackgroundGradientStart,
            backgroundGradientEnd: linksBackgroundGradientEnd,
            isBackgroundColorGradient: isLinksBackgroundColorGradient,
            cornerRadius: linkCornerRadius,
            cornerStyle: linkCornerStyle
        )
    }
}

// MARK: - Functions:

private extension LinksView {
    
    // MARK: - Private functions:
    
    /// Returns a 'Bool' value indicating whether or not the title of the given link should be shown at all:
    private func isShowingTitle(_ link: NT_Link) -> Bool {
        link.isShowingTitle
    }
    
    /// Returns the title of the given link:
    private func title(_ link: NT_Link) -> String {
        link.title
    }
    
    /// Returns a 'Bool' value indicating whether or not the title of the given link should be localized:
    private func isTitleLocalized(_ link: NT_Link) -> Bool {
        link.isTitleLocalized
    }
    
    /// Returns a 'Bool' value indicating whether or not the subtitle of the given link should be shown at all:
    private func isShowingSubtitle(_ link: NT_Link) -> Bool {
        link.isShowingSubtitle
    }
    
    /// Returns the subtitle of the given link:
    private func subtitle(_ link: NT_Link) -> String {
        link.subtitle
    }
    
    /// Returns a 'Bool' value indicating whether or not the subtitle of the given link should be localized:
    private func isSubtitleLocalized(_ link: NT_Link) -> Bool {
        link.isSubtitleLocalized
    }
    
    /// Returns a 'Bool' value indicating whether or not the icon of the given link should be shown at all:
    private func isShowingIcon(_ link: NT_Link) -> Bool {
        link.isShowingIcon
    }
    
    /// Returns the icon of the given link:
    private func icon(_ link: NT_Link) -> String {
        link.icon
    }
    
    /// Returns a 'Bool' value indicating whether or not the divider should be shown that is based on the given link:
    private func isShowingDivider(_ link: NT_Link) -> Bool {
        if isShowingDivider,
           let lastLink: NT_Link = links.last {
            return lastLink.id != link.id
        } else {
            return false
        }
    }
    
    /// Returns the URL of the given link:
    private func url(_ link: NT_Link) -> URL {
        link.url
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        LinksView(
            links: NT_Link.example,
            titleFont: .headline,
            titleTextCase: .none,
            titleAlignment: .leading,
            titleLineSpacing: 0,
            titleColor: .primary,
            subtitleFont: .subheadline,
            subtitleTextCase: .none,
            subtitleAlignment: .leading,
            subtitleLineSpacing: 0,
            subtitleColor: .secondary,
            titleSubtitleAlignment: .leading,
            titleSubtitleSpacing: 4,
            titleSubtitleMaxWidth: .infinity,
            titleSubtitleMaxWidthAlignment: .leading,
            iconSymbolVariant: .fill,
            iconFont: .system(
                size: 17,
                weight: .semibold,
                design: .default
            ),
            iconColor: .accent,
            iconGradientStart: .blueGradientStart,
            iconGradientEnd: .blueGradientEnd,
            isIconColorGradient: true,
            iconFrame: nil,
            linkAlignment: .horizontal,
            linkVerticalAlignment: .top,
            linkHorizontalAlignment: .leading,
            linkSpacing: 12,
            linkVerticalPadding: 12,
            linkHorizontalPadding: 12,
            isShowingLinkBackground: true,
            linkBackgroundColor: .init(.secondarySystemGroupedBackground),
            linksBackgroundGradientStart: .blueGradientStart,
            linksBackgroundGradientEnd: .blueGradientEnd,
            isLinksBackgroundColorGradient: false,
            linkCornerRadius: 16,
            linkCornerStyle: .continuous,
            isShowingDivider: false,
            dividerWidth: nil,
            dividerHeight: 1,
            dividerColor: .init(.systemGray),
            dividerCornerRadius: 0.5,
            dividerCornerStyle: .continuous,
            alignment: .vertical,
            verticalAlignment: .top,
            horizontalAlignment: .leading,
            spacing: 16,
            verticalPadding: 0,
            horizontalPadding: 0,
            isShowingBackground: false,
            backgroundColor: .init(.secondarySystemGroupedBackground),
            backgroundGradientStart: .blueGradientStart,
            backgroundGradientEnd: .blueGradientEnd,
            isBackgroundColorGradient: false,
            cornerRadius: 0,
            cornerStyle: .continuous
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
