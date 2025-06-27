//
//  LabelView.swift
//  Native
//

import SwiftUI

struct LabelView: View {
    
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
    private let titleColor: Color?
    
    /// Starting color of the gradient of the title if applicable:
    private let titleGradientStart: Color
    
    /// Ending color of the gradient of the title if applicable:
    private let titleGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the title should have a gradient applied to it:
    private let isTitleColorGradient: Bool
    
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
    private let subtitleColor: Color?
    
    /// Starting color of the gradient of the subtitle if applicable:
    private let subtitleGradientStart: Color
    
    /// Ending color of the gradient of the subtitle if applicable:
    private let subtitleGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the subtitle should have a gradient applied to it:
    private let isSubtitleColorGradient: Bool
    
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
    
    /// An actual badge to display:
    private let badge: String
    
    /// 'Bool' value indicating whether or not the badge should be localized:
    private let isBadgeLocalized: Bool
    
    /// Horizontal alignment of the view:
    private let horizontalAlignment: HorizontalAlignment
    
    /// Spacing between the content of the view:
    private let spacing: Double
    
    /// Style of the label:
    private let style: NT_LabelStyle
    
    /// Vertical padding around the content of the view:
    private let verticalPadding: Double
    
    /// Horizontal padding around the content of the view:
    private let horizontalPadding: Double
    
    /// 'Bool' value indicating whether or not the label is displayed in the sidebar which is needed to handle its tint color correctly:
    private let isSidebar: Bool
    
    /// 'Bool' value indicating whether or not the loading indicator should be shown at all:
    private let isLoading: Bool
    
    /// Color of the loading indicator:
    private let loadingIndicatorColor: Color
    
    /// Scale of the loading indicator ('1' is the default scale, anything that is more than one will increase the size of the indicator, but anything that is less than one will decrease its size):
    private let loadingIndicatorScale: Double
    
    /// Size of the frame of the loading indicator (If needed, can simply be 'nil'):
    private let loadingIndicatorFrame: CGFloat?
    
    init(
        icon: String = Icons.mailStack,
        iconSymbolVariant: SymbolVariants = .fill,
        iconColor: Color = .accent,
        iconGradientStart: Color = .blueGradientStart,
        iconGradientEnd: Color = .blueGradientEnd,
        isIconColorGradient: Bool = true,
        isShowingIconBackground: Bool = false,
        iconBackgroundColor: Color = .accent,
        iconBackgroundGradientStart: Color = .blueGradientStart,
        iconBackgroundGradientEnd: Color = .blueGradientEnd,
        isIconBackgroundColorGradient: Bool = false,
        iconSize: NT_IconSize = .twentyFourPixels,
        isShowingTitle: Bool = true,
        title: String,
        isTitleLocalized: Bool = true,
        titleFont: Font = .headline,
        titleTextCase: Text.Case? = .none,
        titleAlignment: TextAlignment = .leading,
        titleLineSpacing: Double = 0,
        titleLineLimit: Int? = nil,
        titleColor: Color? = .primary,
        titleGradientStart: Color = .blueGradientStart,
        titleGradientEnd: Color = .blueGradientEnd,
        isTitleColorGradient: Bool = false,
        isShowingSubtitle: Bool = false,
        subtitle: String = "",
        isSubtitleLocalized: Bool = true,
        subtitleFont: Font = .subheadline,
        subtitleTextCase: Text.Case? = .none,
        subtitleAlignment: TextAlignment = .leading,
        subtitleLineSpacing: Double = 0,
        subtitleLineLimit: Int? = nil,
        subtitleColor: Color? = .secondary,
        subtitleGradientStart: Color = .blueGradientStart,
        subtitleGradientEnd: Color = .blueGradientEnd,
        isSubtitleColorGradient: Bool = false,
        titleSubtitleAlignment: HorizontalAlignment = .leading,
        titleSubtitleSpacing: Double = 4,
        titleSubtitleMaxWidth: CGFloat? = nil,
        titleSubtitleMaxWidthAlignment: Alignment = .leading,
        isShowingBadge: Bool = false,
        badge: String = "",
        isBadgeLocalized: Bool = true,
        horizontalAlignment: HorizontalAlignment = .leading,
        spacing: Double = 12,
        style: NT_LabelStyle = .none,
        verticalPadding: Double = 0,
        horizontalPadding: Double = 0,
        isSidebar: Bool = false,
        isLoading: Bool = false,
        loadingIndicatorColor: Color = .secondary,
        loadingIndicatorScale: Double = 1,
        loadingIndicatorFrame: CGFloat? = nil
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
        self.isShowingTitle = isShowingTitle
        self.title = title
        self.isTitleLocalized = isTitleLocalized
        self.titleFont = titleFont
        self.titleTextCase = titleTextCase
        self.titleAlignment = titleAlignment
        self.titleLineSpacing = titleLineSpacing
        self.titleLineLimit = titleLineLimit
        self.titleColor = titleColor
        self.titleGradientStart = titleGradientStart
        self.titleGradientEnd = titleGradientEnd
        self.isTitleColorGradient = isTitleColorGradient
        self.isShowingSubtitle = isShowingSubtitle
        self.subtitle = subtitle
        self.isSubtitleLocalized = isSubtitleLocalized
        self.subtitleFont = subtitleFont
        self.subtitleTextCase = subtitleTextCase
        self.subtitleAlignment = subtitleAlignment
        self.subtitleLineSpacing = subtitleLineSpacing
        self.subtitleLineLimit = subtitleLineLimit
        self.subtitleColor = subtitleColor
        self.subtitleGradientStart = subtitleGradientStart
        self.subtitleGradientEnd = subtitleGradientEnd
        self.isSubtitleColorGradient = isSubtitleColorGradient
        self.titleSubtitleAlignment = titleSubtitleAlignment
        self.titleSubtitleSpacing = titleSubtitleSpacing
        self.titleSubtitleMaxWidth = titleSubtitleMaxWidth
        self.titleSubtitleMaxWidthAlignment = titleSubtitleMaxWidthAlignment
        self.isShowingBadge = isShowingBadge
        self.badge = badge
        self.isBadgeLocalized = isBadgeLocalized
        self.horizontalAlignment = horizontalAlignment
        self.spacing = spacing
        self.style = style
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
        self.isSidebar = isSidebar
        self.isLoading = isLoading
        self.loadingIndicatorColor = loadingIndicatorColor
        self.loadingIndicatorScale = loadingIndicatorScale
        self.loadingIndicatorFrame = loadingIndicatorFrame
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
            .localizedListBadge(
                isShowing: isShowingBadge,
                badge: badge,
                isLocalized: isBadgeLocalized
            )
            .padding(
                .vertical,
                verticalPadding
            )
            .padding(
                .horizontal,
                horizontalPadding
            )
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Item:

private extension LabelView {
    @ViewBuilder
    private var item: some View {
        switch style {
        case .none: itemContent
        case .titleAndIcon: titleAndIconItemContent
        case .titleOnly: titleOnlyItemContent
        case .iconOnly: iconOnlyItemContent
        }
    }
    
    private var titleAndIconItemContent: some View {
        itemContent
            .labelStyle(.titleAndIcon)
    }
    
    private var titleOnlyItemContent: some View {
        itemContent
            .labelStyle(.titleOnly)
    }
    
    private var iconOnlyItemContent: some View {
        itemContent
            .labelStyle(.iconOnly)
    }
    
    @ViewBuilder
    private var itemContent: some View {
        if isLoading {
            loading
        } else {
            label
        }
    }
}

// MARK: - Label:

private extension LabelView {
    @ViewBuilder
    private var label: some View {
        if shouldMoveContent {
            verticalLabel
        } else {
            labelContent
        }
    }
    
    private var verticalLabel: some View {
        VStack(
            alignment: horizontalAlignment,
            spacing: spacing
        ) {
            verticalLabelContent
        }
    }
    
    @ViewBuilder
    private var verticalLabelContent: some View {
        iconContent
        titleSubtitle
    }
    
    private var labelContent: some View {
        Label {
            titleSubtitle
        } icon: {
            iconContent
        }
    }
}

// MARK: - Loading:

private extension LabelView {
    private var loading: some View {
        LoadingView(
            isShowing: isLoading,
            color: loadingIndicatorColor,
            scale: loadingIndicatorScale,
            frame: loadingIndicatorFrame
        )
    }
}

// MARK: - Icon:

private extension LabelView {
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
            size: iconSize,
            isSidebar: isSidebar
        )
    }
}

// MARK: - Title and subtitle:

private extension LabelView {
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
            titleGradientStart: titleGradientStart,
            titleGradientEnd: titleGradientEnd,
            isTitleColorGradient: isTitleColorGradient,
            isShowingSubtitle: isShowingSubtitle,
            subtitle: subtitle,
            isSubtitleLocalized: isSubtitleLocalized,
            subtitleFont: subtitleFont,
            subtitleTextCase: subtitleTextCase,
            subtitleAlignment: subtitleAlignment,
            subtitleLineSpacing: subtitleLineSpacing,
            subtitleLineLimit: subtitleLineLimit,
            subtitleColor: subtitleColor,
            subtitleGradientStart: subtitleGradientStart,
            subtitleGradientEnd: subtitleGradientEnd,
            isSubtitleColorGradient: isSubtitleColorGradient,
            alignment: titleSubtitleAlignment,
            spacing: titleSubtitleSpacing,
            maxWidth: titleSubtitleMaxWidth,
            maxWidthAlignment: titleSubtitleMaxWidthAlignment
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        LabelView(
            icon: Icons.mailStack,
            iconSymbolVariant: .fill,
            iconColor: .accent,
            iconGradientStart: .blueGradientStart,
            iconGradientEnd: .blueGradientEnd,
            isIconColorGradient: true,
            isShowingIconBackground: false,
            iconBackgroundColor: .accent,
            iconBackgroundGradientStart: .blueGradientStart,
            iconBackgroundGradientEnd: .blueGradientEnd,
            isIconBackgroundColorGradient: false,
            iconSize: .twentyFourPixels,
            isShowingTitle: true,
            title: "Title",
            isTitleLocalized: true,
            titleFont: .headline,
            titleTextCase: .none,
            titleAlignment: .leading,
            titleLineSpacing: 0,
            titleLineLimit: nil,
            titleColor: .primary,
            titleGradientStart: .blueGradientStart,
            titleGradientEnd: .blueGradientEnd,
            isTitleColorGradient: false,
            isShowingSubtitle: true,
            subtitle: "Subtitle",
            isSubtitleLocalized: true,
            subtitleFont: .subheadline,
            subtitleTextCase: .none,
            subtitleAlignment: .leading,
            subtitleLineSpacing: 0,
            subtitleLineLimit: nil,
            subtitleColor: .secondary,
            subtitleGradientStart: .blueGradientStart,
            subtitleGradientEnd: .blueGradientEnd,
            isSubtitleColorGradient: false,
            titleSubtitleAlignment: .leading,
            titleSubtitleSpacing: 4,
            titleSubtitleMaxWidth: nil,
            titleSubtitleMaxWidthAlignment: .leading,
            isShowingBadge: true,
            badge: "Badge",
            isBadgeLocalized: true,
            horizontalAlignment: .leading,
            spacing: 12,
            style: .none,
            verticalPadding: 12,
            horizontalPadding: 12,
            isSidebar: false,
            isLoading: false,
            loadingIndicatorColor: .secondary,
            loadingIndicatorScale: 1,
            loadingIndicatorFrame: nil
        )
        .listRowInsets(.init(.zero))
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(title: "Preview")
    .navigationStack()
}
