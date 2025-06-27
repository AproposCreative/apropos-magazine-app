//
//  AvatarTitleValueSubtitleView.swift
//  Native
//

import SwiftUI

struct AvatarTitleValueSubtitleView: View {
    
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
    
    /// 'Bool' value indicating whether or not the value should be shown at all:
    private let isShowingValue: Bool
    
    /// An actual value to display if applicable:
    private let value: String
    
    /// 'Bool' value indicating whether or not the value should be localized if applicable:
    private let isValueLocalized: Bool
    
    /// Font of the value if applicable:
    private let valueFont: Font
    
    /// Text case of the value if applicable:
    private let valueTextCase: Text.Case?
    
    /// Alignment of the value if applicable:
    private let valueAlignment: TextAlignment
    
    /// Additional spacing between the multiple lines of the value if applicable:
    private let valueLineSpacing: Double
    
    /// Color of the value if applicable:
    private let valueColor: Color
    
    /// Starting color of the gradient of the value if applicable:
    private let valueGradientStart: Color
    
    /// Ending color of the gradient of the value if applicable:
    private let valueGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the value should have a gradient applied to it if applicable:
    private let isValueColorGradient: Bool
    
    /// Alignment of the title and the value:
    private let titleValueAlignment: VerticalAlignment
    
    /// Spacing between the title and the value:
    private let titleValueSpacing: Double
    
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
    
    /// Starting color of the gradient of the subtitle if applicable:
    private let subtitleGradientStart: Color
    
    /// Ending color of the gradient of the subtitle if applicable:
    private let subtitleGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the subtitle should have a gradient applied to it:
    private let isSubtitleColorGradient: Bool
    
    /// Alignment of the title, value, and the subtitle:
    private let titleValueSubtitleAlignment: HorizontalAlignment
    
    /// Spacing between the title, value, and the subtitle:
    private let titleValueSubtitleSpacing: Double
    
    /// Maximum width of the title, value, and the subtitle:
    private let titleValueSubtitleMaxWidth: CGFloat?
    
    /// Alignment of the title, value, and the subtitle if they have a maximum width applied to them:
    private let titleValueSubtitleMaxWidthAlignment: Alignment
    
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
        avatarInitialsFont: Font = .system(
            size: 20,
            weight: .bold,
            design: .default
        ),
        avatarInitialsColor: Color = .white,
        avatarInitialsGradientStart: Color = .blueGradientStart,
        avatarInitialsGradientEnd: Color = .blueGradientEnd,
        isAvatarInitialsColorGradient: Bool = false,
        avatarIcon: String = Icons.person,
        avatarIconSymbolVariant: SymbolVariants = .fill,
        avatarIconFont: Font = .system(
            size: 22,
            weight: .semibold,
            design: .default
        ),
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
        titleGradientStart: Color = .blueGradientStart,
        titleGradientEnd: Color = .blueGradientEnd,
        isTitleColorGradient: Bool = false,
        titleMaxWidth: CGFloat? = .infinity,
        titleMaxWidthAlignment: Alignment = .leading,
        isShowingValue: Bool = true,
        value: String,
        isValueLocalized: Bool = false,
        valueFont: Font = .footnote,
        valueTextCase: Text.Case? = .none,
        valueAlignment: TextAlignment = .trailing,
        valueLineSpacing: Double = 0,
        valueColor: Color = .secondary,
        valueGradientStart: Color = .blueGradientStart,
        valueGradientEnd: Color = .blueGradientEnd,
        isValueColorGradient: Bool = false,
        titleValueAlignment: VerticalAlignment = .top,
        titleValueSpacing: Double = 12,
        isShowingSubtitle: Bool = true,
        subtitle: String,
        isSubtitleLocalized: Bool = true,
        subtitleFont: Font = .subheadline,
        subtitleTextCase: Text.Case? = .none,
        subtitleAlignment: TextAlignment = .leading,
        subtitleLineSpacing: Double = 0,
        subtitleLineLimit: Int? = nil,
        subtitleColor: Color = .secondary,
        subtitleGradientStart: Color = .blueGradientStart,
        subtitleGradientEnd: Color = .blueGradientEnd,
        isSubtitleColorGradient: Bool = false,
        titleValueSubtitleAlignment: HorizontalAlignment = .leading,
        titleValueSubtitleSpacing: Double = 4,
        titleValueSubtitleMaxWidth: CGFloat? = .infinity,
        titleValueSubtitleMaxWidthAlignment: Alignment = .leading,
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
        self.titleGradientStart = titleGradientStart
        self.titleGradientEnd = titleGradientEnd
        self.isTitleColorGradient = isTitleColorGradient
        self.titleMaxWidth = titleMaxWidth
        self.titleMaxWidthAlignment = titleMaxWidthAlignment
        self.isShowingValue = isShowingValue
        self.value = value
        self.isValueLocalized = isValueLocalized
        self.valueFont = valueFont
        self.valueTextCase = valueTextCase
        self.valueAlignment = valueAlignment
        self.valueLineSpacing = valueLineSpacing
        self.valueColor = valueColor
        self.valueGradientStart = valueGradientStart
        self.valueGradientEnd = valueGradientEnd
        self.isValueColorGradient = isValueColorGradient
        self.titleValueAlignment = titleValueAlignment
        self.titleValueSpacing = titleValueSpacing
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
        self.titleValueSubtitleAlignment = titleValueSubtitleAlignment
        self.titleValueSubtitleSpacing = titleValueSubtitleSpacing
        self.titleValueSubtitleMaxWidth = titleValueSubtitleMaxWidth
        self.titleValueSubtitleMaxWidthAlignment = titleValueSubtitleMaxWidthAlignment
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

private extension AvatarTitleValueSubtitleView {
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
        avatar
        titleValueSubtitle
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
            alignment: titleValueAlignment,
            spacing: titleValueSpacing
        ) {
            verticalItemHeaderContent
        }
    }
    
    @ViewBuilder
    private var verticalItemHeaderContent: some View {
        avatar
        verticalItemHeaderValue
    }
    
    private var verticalItemHeaderValue: some View {
        valueContent
            .frame(
                maxWidth: .infinity,
                alignment: .trailing
            )
    }
    
    private var verticalItemTitleSubtitle: some View {
        VStack(
            alignment: titleValueSubtitleAlignment,
            spacing: titleValueSubtitleSpacing
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

// MARK: - Avatar:

private extension AvatarTitleValueSubtitleView {
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

// MARK: - Title, value, and subtitle:

private extension AvatarTitleValueSubtitleView {
    private var titleValueSubtitle: some View {
        titleValueSubtitleContent
            .frame(
                maxWidth: titleValueSubtitleMaxWidth,
                alignment: titleValueSubtitleMaxWidthAlignment
            )
    }
    
    private var titleValueSubtitleContent: some View {
        VStack(
            alignment: titleValueSubtitleAlignment,
            spacing: titleValueSubtitleSpacing
        ) {
            titleValueSubtitleItem
        }
    }
    
    @ViewBuilder
    private var titleValueSubtitleItem: some View {
        titleValue
        subtitleContent
    }
    
    private var titleValue: some View {
        HStack(
            alignment: titleValueAlignment,
            spacing: titleValueSpacing
        ) {
            titleValueContent
        }
    }
    
    @ViewBuilder
    private var titleValueContent: some View {
        titleContent
        valueContent
    }
}

// MARK: - Title:

private extension AvatarTitleValueSubtitleView {
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
            .lineLimit(titleLineLimit)
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

// MARK: - Value:

private extension AvatarTitleValueSubtitleView {
    @ViewBuilder
    private var valueContent: some View {
        if isShowingValue {
            valueItem
        }
    }
    
    private var valueItem: some View {
        valueItemContent
            .font(valueFont)
            .textCase(valueTextCase)
            .multilineTextAlignment(valueAlignment)
            .lineSpacing(valueLineSpacing)
            .foregroundGradient(
                color: valueColor,
                gradientStart: valueGradientStart,
                gradientEnd: valueGradientEnd,
                isGradient: isValueColorGradient
            )
    }
    
    @ViewBuilder
    private var valueItemContent: some View {
        if isValueLocalized {
            Text(.init(value))
        } else {
            Text(value)
        }
    }
}

// MARK: - Subtitle:

private extension AvatarTitleValueSubtitleView {
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
            .lineLimit(subtitleLineLimit)
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
        AvatarTitleValueSubtitleView(
            avatarType: .initials,
            avatarInitials: "AL",
            avatarInitialsFont: .system(
                size: 20,
                weight: .bold,
                design: .default
            ),
            avatarInitialsColor: .white,
            avatarInitialsGradientStart: .blueGradientStart,
            avatarInitialsGradientEnd: .blueGradientEnd,
            isAvatarInitialsColorGradient: false,
            avatarIcon: Icons.person,
            avatarIconSymbolVariant: .fill,
            avatarIconFont: .system(
                size: 22,
                weight: .semibold,
                design: .default
            ),
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
            titleGradientStart: .blueGradientStart,
            titleGradientEnd: .blueGradientEnd,
            isTitleColorGradient: false,
            titleMaxWidth: .infinity,
            titleMaxWidthAlignment: .leading,
            isShowingValue: true,
            value: "Value",
            isValueLocalized: false,
            valueFont: .footnote,
            valueTextCase: .none,
            valueAlignment: .trailing,
            valueLineSpacing: 0,
            valueColor: .secondary,
            valueGradientStart: .blueGradientStart,
            valueGradientEnd: .blueGradientEnd,
            isValueColorGradient: false,
            titleValueAlignment: .top,
            titleValueSpacing: 12,
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
            titleValueSubtitleAlignment: .leading,
            titleValueSubtitleSpacing: 4,
            titleValueSubtitleMaxWidth: .infinity,
            titleValueSubtitleMaxWidthAlignment: .leading,
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
