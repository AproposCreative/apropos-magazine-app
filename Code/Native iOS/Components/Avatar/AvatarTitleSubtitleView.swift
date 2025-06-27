//
//  AvatarTitleSubtitleView.swift
//  Native
//

import SwiftUI

struct AvatarTitleSubtitleView: View {
    
    // MARK: - Private properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    /// An actual type of the avatar:
    private let avatarType: NT_AvatarType
    
    /// Initials of the avatar to display:
    private let avatarInitials: String
    
    /// Font of the initials:
    private let avatarInitialsFont: Font
    
    /// Color of the initials:
    private let avatarInitialsColor: Color
    
    /// Starting color of the gradient of the initials if applicable:
    private let avatarInitialsGradientStart: Color
    
    /// Ending color of the gradient of the initials if applicable:
    private let avatarInitialsGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the initials should have a gradient applied to it:
    private let isAvatarInitialsColorGradient: Bool
    
    /// Icon of the avatar to display:
    private let avatarIcon: String
    
    /// Symbol variant of the icon of the avatar:
    private let avatarIconSymbolVariant: SymbolVariants
    
    /// Font of the icon of the avatar:
    private let avatarIconFont: Font
    
    /// Color of the icon of the avatar:
    private let avatarIconColor: Color
    
    /// Starting color of the gradient of the icon of the avatar if applicable:
    private let avatarIconGradientStart: Color
    
    /// Ending color of the gradient of the icon of the avatar if applicable:
    private let avatarIconGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the icon of the avatar should have a gradient applied to it:
    private let isAvatarIconColorGradient: Bool
    
    /// Image of the avatar to display:
    private let avatarImage: Image
    
    /// Color of the avatar:
    private let avatarColor: Color
    
    /// Starting color of the gradient of the avatar if applicable:
    private let avatarGradientStart: Color
    
    /// Ending color of the gradient of the avatar if applicable:
    private let avatarGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the avatar should have a gradient applied to it:
    private let isAvatarGradient: Bool
    
    /// Size of the frame of the avatar:
    private let avatarFrame: Double
    
    /// Radius of the rounded corners of the avatar:
    private let avatarCornerRadius: Double
    
    /// Style of the rounded corners of the avatar:
    private let avatarCornerStyle: RoundedCornerStyle
    
    /// 'Bool' value indicating whether or not the indicator of the avatar should be shown at all:
    private let isShowingAvatarIndicator: Bool
    
    /// Size of the frame of the indicator of the avatar:
    private let avatarIndicatorFrame: Double
    
    /// Color of the border of the indicator of the avatar:
    private let avatarIndicatorBorderColor: Color
    
    /// Width of the border of the indicator of the avatar:
    private let avatarIndicatorBorderWidth: Double
    
    /// Accessibility label of the indicator of the avatar if applicable:
    private let avatarIndicatorAccessibilityLabel: String
    
    /// 'Bool' value indicating whether or not the accessibility label of the indicator should be localized:
    private let isAvatarIndicatorAccessibilityLabelLocalized: Bool
    
    /// Alignment of the indicator of the avatar:
    private let avatarIndicatorAlignment: Alignment
    
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
        avatarType: NT_AvatarType = .initials,
        avatarInitials: String = "AL",
        avatarInitialsFont: Font = .title3.weight(.bold),
        avatarInitialsColor: Color = .white,
        avatarInitialsGradientStart: Color = .blueGradientStart,
        avatarInitialsGradientEnd: Color = .blueGradientEnd,
        isAvatarInitialsColorGradient: Bool = false,
        avatarIcon: String = Icons.person,
        avatarIconSymbolVariant: SymbolVariants = .fill,
        avatarIconFont: Font = .title2.weight(.semibold),
        avatarIconColor: Color = .white,
        avatarIconGradientStart: Color = .blueGradientStart,
        avatarIconGradientEnd: Color = .blueGradientEnd,
        isAvatarIconColorGradient: Bool = false,
        avatarImage: Image = .init(.account1),
        avatarColor: Color = .accent,
        avatarGradientStart: Color = .blueGradientStart,
        avatarGradientEnd: Color = .blueGradientEnd,
        isAvatarGradient: Bool = true,
        avatarFrame: Double = 48,
        avatarCornerRadius: Double = 24,
        avatarCornerStyle: RoundedCornerStyle = .continuous,
        isShowingAvatarIndicator: Bool = false,
        avatarIndicatorFrame: Double = 14,
        avatarIndicatorBorderColor: Color = .init(.systemBackground),
        avatarIndicatorBorderWidth: Double = 2,
        avatarIndicatorAccessibilityLabel: String = "",
        isAvatarIndicatorAccessibilityLabelLocalized: Bool = true,
        avatarIndicatorAlignment: Alignment = .topTrailing,
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
        self.avatarType = avatarType
        self.avatarInitials = avatarInitials
        self.avatarInitialsFont = avatarInitialsFont
        self.avatarInitialsColor = avatarInitialsColor
        self.avatarInitialsGradientStart = avatarInitialsGradientStart
        self.avatarInitialsGradientEnd = avatarInitialsGradientEnd
        self.isAvatarInitialsColorGradient = isAvatarInitialsColorGradient
        self.avatarIcon = avatarIcon
        self.avatarIconSymbolVariant = avatarIconSymbolVariant
        self.avatarIconFont = avatarIconFont
        self.avatarIconColor = avatarIconColor
        self.avatarIconGradientStart = avatarIconGradientStart
        self.avatarIconGradientEnd = avatarIconGradientEnd
        self.isAvatarIconColorGradient = isAvatarIconColorGradient
        self.avatarImage = avatarImage
        self.avatarColor = avatarColor
        self.avatarGradientStart = avatarGradientStart
        self.avatarGradientEnd = avatarGradientEnd
        self.isAvatarGradient = isAvatarGradient
        self.avatarFrame = avatarFrame
        self.avatarCornerRadius = avatarCornerRadius
        self.avatarCornerStyle = avatarCornerStyle
        self.isShowingAvatarIndicator = isShowingAvatarIndicator
        self.avatarIndicatorFrame = avatarIndicatorFrame
        self.avatarIndicatorBorderColor = avatarIndicatorBorderColor
        self.avatarIndicatorBorderWidth = avatarIndicatorBorderWidth
        self.avatarIndicatorAccessibilityLabel = avatarIndicatorAccessibilityLabel
        self.isAvatarIndicatorAccessibilityLabelLocalized = isAvatarIndicatorAccessibilityLabelLocalized
        self.avatarIndicatorAlignment = avatarIndicatorAlignment
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

private extension AvatarTitleSubtitleView {
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
        avatar
        titleSubtitle
    }
}

// MARK: - Avatar:

private extension AvatarTitleSubtitleView {
    private var avatar: some View {
        AvatarView(
            type: avatarType,
            initials: avatarInitials,
            initialsFont: avatarInitialsFont,
            initialsColor: avatarInitialsColor,
            initialsGradientStart: avatarInitialsGradientStart,
            initialsGradientEnd: avatarInitialsGradientEnd,
            isInitialsColorGradient: isAvatarInitialsColorGradient,
            icon: avatarIcon,
            iconSymbolVariant: avatarIconSymbolVariant,
            iconFont: avatarIconFont,
            iconColor: avatarIconColor,
            iconGradientStart: avatarIconGradientStart,
            iconGradientEnd: avatarIconGradientEnd,
            isIconColorGradient: isAvatarIconColorGradient,
            image: avatarImage,
            color: avatarColor,
            gradientStart: avatarGradientStart,
            gradientEnd: avatarGradientEnd,
            isGradient: isAvatarGradient,
            frame: avatarFrame,
            cornerRadius: avatarCornerRadius,
            cornerStyle: avatarCornerStyle,
            isShowingIndicator: isShowingAvatarIndicator,
            indicatorFrame: avatarIndicatorFrame,
            indicatorBorderColor: avatarIndicatorBorderColor,
            indicatorBorderWidth: avatarIndicatorBorderWidth,
            indicatorAccessibilityLabel: avatarIndicatorAccessibilityLabel,
            isIndicatorAccessibilityLabelLocalized: isAvatarIndicatorAccessibilityLabelLocalized,
            indicatorAlignment: avatarIndicatorAlignment
        )
    }
}

// MARK: - Title and subtitle:

private extension AvatarTitleSubtitleView {
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

// MARK: - Preview:

#Preview {
    ScrollView {
        AvatarTitleSubtitleView(
            avatarType: .initials,
            avatarInitials: "AL",
            avatarInitialsFont: .title3.weight(.bold),
            avatarInitialsColor: .white,
            avatarInitialsGradientStart: .blueGradientStart,
            avatarInitialsGradientEnd: .blueGradientEnd,
            isAvatarInitialsColorGradient: false,
            avatarIcon: Icons.person,
            avatarIconSymbolVariant: .fill,
            avatarIconFont: .title2.weight(.semibold),
            avatarIconColor: .white,
            avatarIconGradientStart: .blueGradientStart,
            avatarIconGradientEnd: .blueGradientEnd,
            isAvatarIconColorGradient: false,
            avatarImage: .init(.account1),
            avatarColor: .accent,
            avatarGradientStart: .blueGradientStart,
            avatarGradientEnd: .blueGradientEnd,
            isAvatarGradient: true,
            avatarFrame: 48,
            avatarCornerRadius: 24,
            avatarCornerStyle: .continuous,
            isShowingAvatarIndicator: true,
            avatarIndicatorFrame: 14,
            avatarIndicatorBorderColor: .init(.systemBackground),
            avatarIndicatorBorderWidth: 2,
            avatarIndicatorAccessibilityLabel: "",
            isAvatarIndicatorAccessibilityLabelLocalized: true,
            avatarIndicatorAlignment: .topTrailing,
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
