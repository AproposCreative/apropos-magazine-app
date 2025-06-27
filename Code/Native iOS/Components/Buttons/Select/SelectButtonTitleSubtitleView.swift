//
//  SelectButtonTitleSubtitleView.swift
//  Native
//

import SwiftUI

struct SelectButtonTitleSubtitleView: View {
    
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
    private let subtitleColor: Color
    
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
    
    /// 'Bool' value indicating whether or not the content of the view should be placed in reverse meaning that the title and the subtitle would be displayed first and the 'Select' button last:
    private let isReversed: Bool
    
    /// Alignment of the view:
    private let alignment: NT_Alignment
    
    /// Vertical alignment of the view:
    private let verticalAlignment: VerticalAlignment
    
    /// Horizontal alignment of the view:
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
    
    /// Width of the border of the view:
    private let borderWidth: Double
    
    /// Color of the border of the view:
    private let borderColor: Color
    
    /// Starting color of the gradient of the border if applicable:
    private let borderGradientStart: Color
    
    /// Ending color of the gradient of the border if applicable:
    private let borderGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the border of the view should have a gradient applied to it:
    private let isBorderGradient: Bool
    
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
        titleGradientStart: Color = .blueGradientStart,
        titleGradientEnd: Color = .blueGradientEnd,
        isTitleColorGradient: Bool = false,
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
        titleSubtitleAlignment: HorizontalAlignment = .leading,
        titleSubtitleSpacing: Double = 4,
        titleSubtitleMaxWidth: CGFloat? = .infinity,
        titleSubtitleMaxWidthAlignment: Alignment = .leading,
        isReversed: Bool = false,
        alignment: NT_Alignment = .horizontal,
        verticalAlignment: VerticalAlignment = .center,
        horizontalAlignment: HorizontalAlignment = .leading,
        spacing: Double = 8,
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
        borderWidth: Double = 0,
        borderColor: Color = .accent,
        borderGradientStart: Color = .blueGradientStart,
        borderGradientEnd: Color = .blueGradientEnd,
        isBorderGradient: Bool = true,
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
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.borderGradientStart = borderGradientStart
        self.borderGradientEnd = borderGradientEnd
        self.isBorderGradient = isBorderGradient
        self.selectButtonAction = selectButtonAction
    }
    
    // MARK: - Private computed properties:
    
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

private extension SelectButtonTitleSubtitleView {
    private var item: some View {
        Button {
            selectButtonAction?()
        } label: {
            label
        }
    }
}

// MARK: - Label:

private extension SelectButtonTitleSubtitleView {
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
                cornerStyle: cornerStyle,
                borderWidth: borderWidth,
                borderColor: borderColor,
                borderGradientStart: borderGradientStart,
                borderGradientEnd: borderGradientEnd,
                isBorderGradient: isBorderGradient
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
            reversedLabelItem
        }
    }
    
    private var verticalLabelContent: some View {
        VStack(
            alignment: horizontalAlignment,
            spacing: spacing
        ) {
            reversedLabelItem
        }
    }
    
    @ViewBuilder
    private var reversedLabelItem: some View {
        if isReversed {
            reversedLabelItemContent
        } else {
            labelItemContent
        }
    }
    
    @ViewBuilder
    private var reversedLabelItemContent: some View {
        titleSubtitle
        selectButton
    }
    
    @ViewBuilder
    private var labelItemContent: some View {
        selectButton
        titleSubtitle
    }
}

// MARK: - Select button:

private extension SelectButtonTitleSubtitleView {
    private var selectButton: some View {
        SelectButtonView(
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
            isSelected: isSelected,
            isShowing: isShowingSelectButton,
            isDisabled: isSelectButtonDisabled,
            action: selectButtonAction
        )
    }
}

// MARK: - Title and subtitle:

private extension SelectButtonTitleSubtitleView {
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
    ScrollView {
        SelectButtonTitleSubtitleView(
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
            titleSubtitleMaxWidth: .infinity,
            titleSubtitleMaxWidthAlignment: .leading,
            isReversed: false,
            alignment: .horizontal,
            verticalAlignment: .center,
            horizontalAlignment: .leading,
            spacing: 8,
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
            cornerStyle: .continuous,
            borderWidth: 0,
            borderColor: .accent,
            borderGradientStart: .blueGradientStart,
            borderGradientEnd: .blueGradientEnd,
            isBorderGradient: true
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
