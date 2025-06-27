//
//  SelectButtonTitleSubtitleBadgesView.swift
//  Native
//

import SwiftUI

struct SelectButtonTitleSubtitleBadgesView: View {
    
    // MARK: - Private properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    /// Icon to display when the value is selected:
    private let selectedIcon: String
    
    /// Symbol variant of the icon to display when the value is selected:
    private let selectedSymbolVariant: SymbolVariants
    
    /// Font of the icon to display when the value is selected:
    private let selectedFont: Font
    
    /// Color of the icon to display when the value is selected:
    private let selectedColor: Color
    
    /// Starting color of the gradient of the icon to display when the value is selected if applicable:
    private let selectedGradientStart: Color
    
    /// Ending color of the gradient of the icon to display when the value is selected if applicable:
    private let selectedGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the icon to display when the value is selected should have a gradient applied to it:
    private let isSelectedGradient: Bool
    
    /// Icon to display when the value is not selected:
    private let unselectedIcon: String
    
    /// Symbol variant of the icon to display when the value is not selected:
    private let unselectedSymbolVariant: SymbolVariants
    
    /// Font of the icon to display when the value is not selected:
    private let unselectedFont: Font
    
    /// Color of the icon to display when the value is not selected:
    private let unselectedColor: Color
    
    /// Starting color of the gradient of the icon to display when the value is not selected if applicable:
    private let unselectedGradientStart: Color
    
    /// Ending color of the gradient of the icon to display when the value is not selected if applicable:
    private let unselectedGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the icon to display when the value is not selected should have a gradient applied to it:
    private let isUnselectedGradient: Bool
    
    /// Size of the frame of the 'Select' button:
    private let selectButtonFrame: CGFloat?
    
    /// Alignment of the frame of the 'Select' button:
    private let selectedButtonFrameAlignment: Alignment
    
    /// 'Bool' value indicating whether or not the value is selected:
    private let isSelected: Bool
    
    /// 'Bool' value indicating whether or not the 'Select' button should be shown at all:
    private let isShowingSelectButton: Bool
    
    /// 'Bool' value indicating whether or not the 'Select' button should be disabled:
    private let isSelectButtonDisabled: Bool
    
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
    
    /// 'Bool' value indicating whether or not the badges should be shown at all:
    private let isShowingBadges: Bool
    
    /// An array of the badges to display:
    private let badges: [NT_Badge]
    
    /// Alignment of the badges:
    private let badgesAlignment: VerticalAlignment
    
    /// Spacing between the badges:
    private let badgesSpacing: Double
    
    /// Alignment of the title, subtitle, and the badges:
    private let titleSubtitleBadgesAlignment: HorizontalAlignment
    
    /// Spacing between the title, subtitle, and the badges:
    private let titleSubtitleBadgesSpacing: Double
    
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
    
    /// An actual action to select if applicable:
    private let selectButtonAction: (() -> ())?
    
    init(
        selectedIcon: String = Icons.checkmarkCircle,
        selectedSymbolVariant: SymbolVariants = .fill,
        selectedFont: Font = .title2.weight(.semibold),
        selectedColor: Color = .accent,
        selectedGradientStart: Color = .blueGradientStart,
        selectedGradientEnd: Color = .blueGradientEnd,
        isSelectedGradient: Bool = true,
        unselectedIcon: String = Icons.circle,
        unselectedSymbolVariant: SymbolVariants = .none,
        unselectedFont: Font = .title2,
        unselectedColor: Color = .init(.systemFill),
        unselectedGradientStart: Color = .blueGradientStart,
        unselectedGradientEnd: Color = .blueGradientEnd,
        isUnselectedGradient: Bool = false,
        selectButtonFrame: CGFloat? = 32,
        selectedButtonFrameAlignment: Alignment = .center,
        isSelected: Bool,
        isShowingSelectButton: Bool = true,
        isSelectButtonDisabled: Bool = false,
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
        isShowingBadges: Bool = true,
        badges: [NT_Badge],
        badgesAlignment: VerticalAlignment = .center,
        badgesSpacing: Double = 8,
        titleSubtitleBadgesAlignment: HorizontalAlignment = .leading,
        titleSubtitleBadgesSpacing: Double = 8,
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
        selectButtonAction: (() -> ())? = nil
    ) {
        
        /// Properties initialization:
        self.selectedIcon = selectedIcon
        self.selectedSymbolVariant = selectedSymbolVariant
        self.selectedFont = selectedFont
        self.selectedColor = selectedColor
        self.selectedGradientStart = selectedGradientStart
        self.selectedGradientEnd = selectedGradientEnd
        self.isSelectedGradient = isSelectedGradient
        self.unselectedIcon = unselectedIcon
        self.unselectedSymbolVariant = unselectedSymbolVariant
        self.unselectedFont = unselectedFont
        self.unselectedColor = unselectedColor
        self.unselectedGradientStart = unselectedGradientStart
        self.unselectedGradientEnd = unselectedGradientEnd
        self.isUnselectedGradient = isUnselectedGradient
        self.selectButtonFrame = selectButtonFrame
        self.selectedButtonFrameAlignment = selectedButtonFrameAlignment
        self.isSelected = isSelected
        self.isShowingSelectButton = isShowingSelectButton
        self.isSelectButtonDisabled = isSelectButtonDisabled
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
        self.isShowingBadges = isShowingBadges
        self.badges = badges
        self.badgesAlignment = badgesAlignment
        self.badgesSpacing = badgesSpacing
        self.titleSubtitleBadgesAlignment = titleSubtitleBadgesAlignment
        self.titleSubtitleBadgesSpacing = titleSubtitleBadgesSpacing
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
        self.selectButtonAction = selectButtonAction
    }
    
    // MARK: - Private computed properties:
    
    /// Content of a 'Bool' value indicating whether or not the badges should be shown at all that is based on the value of the 'isShowingBadges' property that was provided, as well as whether or not an array of the badges that was provided is empty:
    private var isShowingBadgesContent: Bool {
        isShowingBadges && !badges.isEmpty
    }
    
    /// Accessibility traits of the 'Select' button to indicate that it's an actual button, as well as whether or not it's currently selected:
    private var selectButtonAccessibilityTraits: AccessibilityTraits {
        isSelected ? [.isButton, .isSelected] : .isButton
    }
    
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
            .buttonStyle(.plain)
            .disabled(isSelectButtonDisabled)
            .accessibilityAddTraits(selectButtonAccessibilityTraits)
    }
}

// MARK: - Item:

private extension SelectButtonTitleSubtitleBadgesView {
    private var item: some View {
        Button {
            selectButtonAction?()
        } label: {
            label
        }
    }
}

// MARK: - Label:

private extension SelectButtonTitleSubtitleBadgesView {
    private var label: some View {
        labelContent
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
    }
    
    @ViewBuilder
    private var labelContent: some View {
        switch alignmentValue {
        case .horizontal: horizontalLabelContent
        case .vertical: verticalLabelContent
        }
    }
    
    private var horizontalLabelContent: some View {
        HStack(
            alignment: verticalAlignment,
            spacing: spacing
        ) {
            labelItem
        }
    }
    
    private var verticalLabelContent: some View {
        VStack(
            alignment: horizontalAlignment,
            spacing: spacing
        ) {
            labelItem
        }
    }
    
    @ViewBuilder
    private var labelItem: some View {
        selectButton
        titleSubtitleBadges
    }
}

// MARK: - Select button:

private extension SelectButtonTitleSubtitleBadgesView {
    @ViewBuilder
    private var selectButton: some View {
        if isShowingSelectButton {
            selectButtonContent
        }
    }
    
    private var selectButtonContent: some View {
        SelectButtonLabelView(
            selectedIcon: selectedIcon,
            selectedSymbolVariant: selectedSymbolVariant,
            selectedFont: selectedFont,
            selectedColor: selectedColor,
            selectedGradientStart: selectedGradientStart,
            selectedGradientEnd: selectedGradientEnd,
            isSelectedGradient: isSelectedGradient,
            unselectedIcon: unselectedIcon,
            unselectedSymbolVariant: unselectedSymbolVariant,
            unselectedFont: unselectedFont,
            unselectedColor: unselectedColor,
            unselectedGradientStart: unselectedGradientStart,
            unselectedGradientEnd: unselectedGradientEnd,
            isUnselectedGradient: isUnselectedGradient,
            frame: selectButtonFrame,
            frameAlignment: selectedButtonFrameAlignment,
            isSelected: isSelected
        )
    }
}

// MARK: - Title, subtitle, and badges:

private extension SelectButtonTitleSubtitleBadgesView {
    private var titleSubtitleBadges: some View {
        VStack(
            alignment: titleSubtitleBadgesAlignment,
            spacing: titleSubtitleBadgesSpacing
        ) {
            titleSubtitleBadgesContent
        }
    }
    
    @ViewBuilder
    private var titleSubtitleBadgesContent: some View {
        titleSubtitle
        badgesContent
    }
}

// MARK: - Title and subtitle:

private extension SelectButtonTitleSubtitleBadgesView {
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

// MARK: - Badges:

private extension SelectButtonTitleSubtitleBadgesView {
    @ViewBuilder
    private var badgesContent: some View {
        if isShowingBadgesContent {
            badgesItem
        }
    }
    
    private var badgesItem: some View {
        badgesItemContent
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .accessibilityElement(children: .combine)
    }
    
    private var badgesItemContent: some View {
        ScrollView(.horizontal) {
            badgesItems
        }
    }
    
    private var badgesItems: some View {
        badgeItemsContent
            .scrollTargetLayout()
    }
    
    private var badgeItemsContent: some View {
        HStack(
            alignment: badgesAlignment,
            spacing: badgesSpacing
        ) {
            badgesItemsItem
        }
    }
    
    private var badgesItemsItem: some View {
        ForEach(
            badges,
            content: badge
        )
    }
    
    private func badge(_ badge: NT_Badge) -> some View {
        BadgeView(
            isShowingIcon: isShowingBadgeIcon(badge),
            icon: badgeIcon(badge),
            iconSymbolVariant: badgeIconSymbolVariant(badge),
            iconColor: badgeIconColor(badge),
            iconGradientStart: badgeIconGradientStart(badge),
            iconGradientEnd: badgeIconGradientEnd(badge),
            isIconColorGradient: isBadgeIconColorGradient(badge),
            title: badgeTitle(badge),
            isTitleLocalized: isBadgeTitleLocalized(badge),
            titleTextCase: badgeTitleTextCase(badge),
            titleAlignment: badgeTitleAlignment(badge),
            titleColor: badgeTitleColor(badge),
            titleGradientStart: badgeTitleGradientStart(badge),
            titleGradientEnd: badgeTitleGradientEnd(badge),
            isTitleColorGradient: isBadgeTitleColorGradient(badge),
            backgroundColor: badgeBackgroundColor(badge),
            backgroundGradientStart: badgeBackgroundGradientStart(badge),
            backgroundGradientEnd: badgeBackgroundGradientEnd(badge),
            isBackgroundColorGradient: isBadgeBackgroundColorGradient(badge),
            isShowingBorder: isShowingBadgeBorder(badge),
            borderColor: badgeBorderColor(badge),
            size: badgeSize(badge)
        )
    }
}

// MARK: - Functions:

private extension SelectButtonTitleSubtitleBadgesView {
    
    // MARK: - Private functions:
    
    /// Returns a 'Bool' value indicating whether or not the icon of the badge should be shown at all:
    func isShowingBadgeIcon(_ badge: NT_Badge) -> Bool {
        badge.isShowingIcon
    }
    
    /// Returns an actual icon of the badge to display if applicable:
    func badgeIcon(_ badge: NT_Badge) -> String {
        badge.icon
    }
    
    /// Returns the symbol variant of the icon of the badge if applicable (It could be '.fill', '.circle', etc.):
    func badgeIconSymbolVariant(_ badge: NT_Badge) -> SymbolVariants {
        badge.iconSymbolVariant
    }
    
    /// Returns the color of the icon of the badge if applicable:
    func badgeIconColor(_ badge: NT_Badge) -> Color {
        badge.iconColor
    }
    
    /// Returns the starting color of the gradient of the icon of the badge if applicable:
    func badgeIconGradientStart(_ badge: NT_Badge) -> Color {
        badge.iconGradientStart
    }
    
    /// Returns the ending color of the gradient of the icon of the badge if applicable:
    func badgeIconGradientEnd(_ badge: NT_Badge) -> Color {
        badge.iconGradientEnd
    }
    
    /// Returns a 'Bool' value indicating whether or not the color of the icon of the badge should have a gradient applied to it if applicable:
    func isBadgeIconColorGradient(_ badge: NT_Badge) -> Bool {
        badge.isIconColorGradient
    }
    
    /// Returns the title of the given badge:
    private func badgeTitle(_ badge: NT_Badge) -> String {
        badge.title
    }
    
    /// Returns a 'Bool' value indicating whether or not the title of the given badge should be localized:
    private func isBadgeTitleLocalized(_ badge: NT_Badge) -> Bool {
        badge.isTitleLocalized
    }
    
    /// Returns the text case of the title of the given badge:
    private func badgeTitleTextCase(_ badge: NT_Badge) -> Text.Case? {
        badge.titleTextCase
    }
    
    /// Returns the alignment of the title of the given badge:
    private func badgeTitleAlignment(_ badge: NT_Badge) -> TextAlignment {
        badge.titleAlignment
    }
    
    /// Returns the color of the title of the given badge:
    private func badgeTitleColor(_ badge: NT_Badge) -> Color {
        badge.titleColor
    }
    
    /// Returns the starting color of the gradient of the title of the given badge:
    private func badgeTitleGradientStart(_ badge: NT_Badge) -> Color {
        badge.titleGradientStart
    }
    
    /// Returns the ending color of the gradient of the title of the given badge:
    private func badgeTitleGradientEnd(_ badge: NT_Badge) -> Color {
        badge.titleGradientEnd
    }
    
    /// Returns a 'Bool' value indicating whether or not the color of the title of the given badge should have a gradient applied to it:
    private func isBadgeTitleColorGradient(_ badge: NT_Badge) -> Bool {
        badge.isTitleColorGradient
    }
    
    /// Returns the background color of the given badge:
    private func badgeBackgroundColor(_ badge: NT_Badge) -> Color {
        badge.backgroundColor
    }
    
    /// Returns the starting color of the gradient of the background of the given badge:
    private func badgeBackgroundGradientStart(_ badge: NT_Badge) -> Color {
        badge.backgroundGradientStart
    }
    
    /// Returns the ending color of the gradient of the background color of the given badge:
    private func badgeBackgroundGradientEnd(_ badge: NT_Badge) -> Color {
        badge.backgroundGradientEnd
    }
    
    /// Returns a 'Bool' value indicating whether or not the background color of the badge should have a gradient applied given to it:
    private func isBadgeBackgroundColorGradient(_ badge: NT_Badge) -> Bool {
        badge.isBackgroundColorGradient
    }
    
    /// Returns a 'Bool' value indicating whether or not the border of the badge should be shown at all:
    private func isShowingBadgeBorder(_ badge: NT_Badge) -> Bool {
        badge.isShowingBorder
    }
    
    /// Returns the color of the border of the given badge:
    private func badgeBorderColor(_ badge: NT_Badge) -> Color {
        badge.borderColor
    }
    
    /// Returns the size of the given badge:
    private func badgeSize(_ badge: NT_Badge) -> NT_BadgeSize {
        badge.size
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        SelectButtonTitleSubtitleBadgesView(
            selectedIcon: Icons.checkmarkCircle,
            selectedSymbolVariant: .fill,
            selectedFont: .title2.weight(.semibold),
            selectedColor: .accent,
            selectedGradientStart: .blueGradientStart,
            selectedGradientEnd: .blueGradientEnd,
            isSelectedGradient: true,
            unselectedIcon: Icons.circle,
            unselectedSymbolVariant: .none,
            unselectedFont: .title2,
            unselectedColor: .init(.systemFill),
            unselectedGradientStart: .blueGradientStart,
            unselectedGradientEnd: .blueGradientEnd,
            isUnselectedGradient: false,
            selectButtonFrame: 32,
            selectedButtonFrameAlignment: .center,
            isSelected: true,
            isShowingSelectButton: true,
            isSelectButtonDisabled: false,
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
            isShowingBadges: true,
            badges: NT_Badge.example,
            badgesAlignment: .center,
            badgesSpacing: 8,
            titleSubtitleBadgesAlignment: .leading,
            titleSubtitleBadgesSpacing: 8,
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
