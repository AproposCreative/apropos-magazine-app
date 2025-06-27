//
//  BannerView.swift
//  Native
//

import SwiftUI

struct BannerView: View {
    
    // MARK: - Private properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    /// 'Bool' value indicating whether or not the banner should be shown at all:
    private let isShowing: Bool
    
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
    
    /// 'Bool' value indicating whether or not the color of the background of the icon should have a gradient applied to it:
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
    
    /// 'Bool' value indicating whether or not the 'Dismiss' button should be shown at all:
    private let isShowingDismissButton: Bool
    
    /// Title of the 'Dismiss' button:
    private let dismissButtonTitle: String
    
    /// 'Bool' value indicating whether or not the title of the 'Dismiss' button should be localized:
    private let isDismissButtonTitleLocalized: Bool
    
    /// Icon of the 'Dismiss' button:
    private let dismissButtonIcon: String
    
    /// Symbol variant of the icon of the 'Dismiss' button:
    private let dismissButtonIconSymbolVariant: SymbolVariants
    
    /// Font of the 'Dismiss' button:
    private let dismissButtonFont: Font
    
    /// Color of the 'Dismiss' button:
    private let dismissButtonColor: Color
    
    /// Frame of the 'Dismiss' button:
    private let dismissFrame: CGFloat?
    
    /// Alignment of the content of the view:
    private let alignment: NT_Alignment
    
    /// Vertical alignment of the content of the view:
    private let verticalAlignment: VerticalAlignment
    
    /// Horizontal alignment of the content of the view:
    private let horizontalAlignment: HorizontalAlignment
    
    /// Spacing between the content of the view:
    private let spacing: Double
    
    /// An array of the buttons to display:
    private let buttons: [NT_Button]
    
    /// Vertical alignment of the buttons:
    private let buttonsVerticalAlignment: VerticalAlignment
    
    /// Horizontal alignment of the buttons:
    private let buttonsHorizontalAlignment: HorizontalAlignment
    
    /// Alignment of the buttons:
    private let buttonsAlignment: NT_Alignment
    
    /// Spacing between the buttons:
    private let buttonsSpacing: Double
    
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
    
    /// An actual action to dismiss the banner if applicable:
    private let dismissAction: (() -> ())?
    
    init(
        isShowing: Bool,
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
        iconBorderColor: Color = .blue,
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
        isShowingDismissButton: Bool = true,
        dismissButtonTitle: String = "Dismiss",
        isDismissButtonTitleLocalized: Bool = true,
        dismissButtonIcon: String = Icons.xmark,
        dismissButtonIconSymbolVariant: SymbolVariants = .fill,
        dismissButtonFont: Font = .headline,
        dismissButtonColor: Color = .init(.tertiaryLabel),
        dismissFrame: CGFloat? = 24,
        alignment: NT_Alignment = .horizontal,
        verticalAlignment: VerticalAlignment = .top,
        horizontalAlignment: HorizontalAlignment = .leading,
        spacing: Double = 12,
        buttons: [NT_Button] = [],
        buttonsVerticalAlignment: VerticalAlignment = .center,
        buttonsHorizontalAlignment: HorizontalAlignment = .center,
        buttonsAlignment: NT_Alignment = .vertical,
        buttonsSpacing: Double = 8,
        verticalPadding: Double = 12,
        horizontalPadding: Double = 12,
        isShowingBackground: Bool = true,
        backgroundColor: Color = .init(.secondarySystemGroupedBackground),
        backgroundGradientStart: Color = .blueGradientStart,
        backgroundGradientEnd: Color = .blueGradientEnd,
        isBackgroundColorGradient: Bool = false,
        cornerRadius: Double = 16,
        cornerStyle: RoundedCornerStyle = .continuous,
        dismissAction: (() -> ())? = nil
    ) {
        
        /// Properties initialization:
        self.isShowing = isShowing
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
        self.isShowingDismissButton = isShowingDismissButton
        self.dismissButtonTitle = dismissButtonTitle
        self.isDismissButtonTitleLocalized = isDismissButtonTitleLocalized
        self.dismissButtonIcon = dismissButtonIcon
        self.dismissButtonIconSymbolVariant = dismissButtonIconSymbolVariant
        self.dismissButtonFont = dismissButtonFont
        self.dismissButtonColor = dismissButtonColor
        self.dismissFrame = dismissFrame
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
        self.horizontalAlignment = horizontalAlignment
        self.spacing = spacing
        self.buttons = buttons
        self.buttonsVerticalAlignment = buttonsVerticalAlignment
        self.buttonsHorizontalAlignment = buttonsHorizontalAlignment
        self.buttonsAlignment = buttonsAlignment
        self.buttonsSpacing = buttonsSpacing
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
        self.isShowingBackground = isShowingBackground
        self.backgroundColor = backgroundColor
        self.backgroundGradientStart = backgroundGradientStart
        self.backgroundGradientEnd = backgroundGradientEnd
        self.isBackgroundColorGradient = isBackgroundColorGradient
        self.cornerRadius = cornerRadius
        self.cornerStyle = cornerStyle
        self.dismissAction = dismissAction
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the buttons should be shown at all:
    private var isShowingButtons: Bool {
        !buttons.isEmpty
    }
    
    /// Value of the alignment of the view that is based on the size of the dynamic type that is currently selected:
    private var alignmentValue: NT_Alignment {
        dynamicTypeSize >= .accessibility1 ? .vertical : alignment
    }
    
    /// Value of the alignment of the buttons that is based on the size of the dynamic type that is currently selected:
    private var buttonsAlignmentValue: NT_Alignment {
        dynamicTypeSize >= .accessibility1 ? .vertical : buttonsAlignment
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

private extension BannerView {
    private var item: some View {
        VStack(
            alignment: horizontalAlignment,
            spacing: spacing
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        horizontalVerticalItem
        buttonsContent
    }
    
    @ViewBuilder
    private var horizontalVerticalItem: some View {
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
        titleSubtitle
        dismissButton
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
        titleSubtitle
    }
    
    private var verticalItemHeader: some View {
        HStack(
            alignment: verticalAlignment,
            spacing: spacing
        ) {
            verticalItemHeaderContent
        }
    }
    
    @ViewBuilder
    private var verticalItemHeaderContent: some View {
        verticalItemHeaderIcon
        dismissButton
    }
    
    private var verticalItemHeaderIcon: some View {
        iconContent
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
    }
}

// MARK: - Icon:

private extension BannerView {
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
            borderColor: iconBorderColor
        )
    }
}

// MARK: - Title and subtitle:

private extension BannerView {
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

// MARK: - Dismiss buttons:

private extension BannerView {
    @ViewBuilder
    private var dismissButton: some View {
        if isShowingDismissButton {
            dismissButtonContent
        }
    }
    
    private var dismissButtonContent: some View {
        dismissButtonItem
            .frame(
                width: dismissFrame,
                height: dismissFrame,
                alignment: .center
            )
    }
    
    private var dismissButtonItem: some View {
        ButtonView(
            title: dismissButtonTitle,
            isTitleLocalized: isDismissButtonTitleLocalized,
            icon: dismissButtonIcon,
            iconSymbolVariant: dismissButtonIconSymbolVariant,
            iconFont: dismissButtonFont,
            iconColor: dismissButtonColor,
            style: .iconOnly,
            verticalPadding: 0,
            horizontalPadding: 0,
            isFullWidth: false,
            isShowingBackground: false,
            cornerRadius: 0
        ) {
            dismissAction?()
        }
    }
}

// MARK: - Buttons:

private extension BannerView {
    @ViewBuilder
    private var buttonsContent: some View {
        if isShowingButtons {
            buttonsItem
        }
    }
    
    @ViewBuilder
    private var buttonsItem: some View {
        switch buttonsAlignmentValue {
        case .vertical: verticalButtonsItemContent
        case .horizontal: horizontalButtonsItemContent
        }
    }
    
    private var verticalButtonsItemContent: some View {
        VStack(
            alignment: buttonsHorizontalAlignment,
            spacing: buttonsSpacing
        ) {
            buttonsItemContent
        }
    }
    
    private var horizontalButtonsItemContent: some View {
        HStack(
            alignment: buttonsVerticalAlignment,
            spacing: buttonsSpacing
        ) {
            buttonsItemContent
        }
    }
    
    private var buttonsItemContent: some View {
        ForEach(
            buttons,
            content: button
        )
    }
    
    private func button(_ button: NT_Button) -> some View {
        ButtonView(
            title: buttonTitle(button),
            isTitleLocalized: isButtonTitleLocalized(button),
            titleFont: buttonTitleFont(button),
            titleTextCase: buttonTitleTextCase(button),
            titleAlignment: buttonTitleAlignment(button),
            titleColor: buttonTitleColor(button),
            titleGradientStart: buttonTitleGradientStart(button),
            titleGradientEnd: buttonTitleGradientEnd(button),
            isTitleColorGradient: isButtonTitleColorGradient(button),
            icon: buttonIcon(button),
            iconSymbolVariant: buttonIconSymbolVariant(button),
            iconFont: buttonIconFont(button),
            iconColor: buttonIconColor(button),
            iconGradientStart: buttonIconGradientStart(button),
            iconGradientEnd: buttonIconGradientEnd(button),
            isIconColorGradient: isButtonIconColorGradient(button),
            style: buttonStyle(button),
            isLoading: isButtonLoading(button),
            loadingIndicatorColor: buttonLoadingIndicatorColor(button),
            loadingIndicatorScale: buttonLoadingIndicatorScale(button),
            loadingIndicatorFrame: buttonLoadingIndicatorFrame(button),
            verticalPadding: buttonVerticalPadding(button),
            horizontalPadding: buttonHorizontalPadding(button),
            isFullWidth: isButtonFullWidth(button),
            alignment: buttonAlignment(button),
            isShowingBackground: isShowingButtonBackground(button),
            backgroundColor: buttonBackgroundColor(button),
            backgroundGradientStart: buttonBackgroundGradientStart(button),
            backgroundGradientEnd: buttonBackgroundGradientEnd(button),
            isBackgroundColorGradient: isButtonBackgroundColorGradient(button),
            cornerRadius: buttonCornerRadius(button),
            cornerStyle: buttonCornerStyle(button),
            role: buttonRole(button),
            isDisabled: isButtonDisabled(button),
            keyboardShortcut: buttonKeyboardShortcut(button),
            action: buttonAction(button)
        )
    }
}

// MARK: - Functions:

private extension BannerView {
    
    // MARK: - Private functions:
    
    /// Returns the title of the given button:
    private func buttonTitle(_ button: NT_Button) -> String {
        button.title
    }
    
    /// Returns a 'Bool' value indicating whether or not the title of the given button should be localized:
    private func isButtonTitleLocalized(_ button: NT_Button) -> Bool {
        button.isTitleLocalized
    }
    
    /// Returns the font of the title of the given button:
    private func buttonTitleFont(_ button: NT_Button) -> Font {
        button.titleFont
    }
    
    /// Returns the text case of the title of the given button:
    private func buttonTitleTextCase(_ button: NT_Button) -> Text.Case? {
        button.titleTextCase
    }
    
    /// Returns the alignment of the title of the given button:
    private func buttonTitleAlignment(_ button: NT_Button) -> TextAlignment {
        button.titleAlignment
    }
    
    /// Returns the color of the title of the given button:
    private func buttonTitleColor(_ button: NT_Button) -> Color? {
        button.titleColor
    }
    
    /// Returns the starting color of the gradient of the title of the given button:
    private func buttonTitleGradientStart(_ button: NT_Button) -> Color {
        button.titleGradientStart
    }
    
    /// Returns the ending color of the gradient of the title of the given button:
    private func buttonTitleGradientEnd(_ button: NT_Button) -> Color {
        button.titleGradientEnd
    }
    
    /// Returns a 'Bool' value indicating whether or not the color of the title of the given button should have a gradient applied to it:
    private func isButtonTitleColorGradient(_ button: NT_Button) -> Bool {
        button.isTitleColorGradient
    }
    
    /// Returns the icon of the given button:
    private func buttonIcon(_ button: NT_Button) -> String {
        button.icon
    }
    
    /// Returns the symbol variant of the icon of the given button:
    private func buttonIconSymbolVariant(_ button: NT_Button) -> SymbolVariants {
        button.iconSymbolVariant
    }
    
    /// Returns the font of the icon of the given button:
    private func buttonIconFont(_ button: NT_Button) -> Font {
        button.iconFont
    }
    
    /// Returns the color of the icon of the given button:
    private func buttonIconColor(_ button: NT_Button) -> Color? {
        button.titleColor
    }
    
    /// Returns the starting color of the gradient of the icon of the given button:
    private func buttonIconGradientStart(_ button: NT_Button) -> Color {
        button.titleGradientStart
    }
    
    /// Returns the ending color of the gradient of the icon of the given button:
    private func buttonIconGradientEnd(_ button: NT_Button) -> Color {
        button.titleGradientEnd
    }
    
    /// Returns a 'Bool' value indicating whether or not the color of the icon of the given button should have a gradient applied to it:
    private func isButtonIconColorGradient(_ button: NT_Button) -> Bool {
        button.isTitleColorGradient
    }
    
    /// Returns the style of the given button:
    private func buttonStyle(_ button: NT_Button) -> NT_LabelStyle {
        button.style
    }
    
    /// Returns a 'Bool' value indicating whether or not the loading indicator of the given button should be shown at all:
    private func isButtonLoading(_ button: NT_Button) -> Bool {
        button.isLoading
    }
    
    /// Returns the color of the loading indicator of the given button:
    private func buttonLoadingIndicatorColor(_ button: NT_Button) -> Color {
        button.loadingIndicatorColor
    }
    
    /// Returns the scale of the loading indicator of the given button:
    private func buttonLoadingIndicatorScale(_ button: NT_Button) -> Double {
        button.loadingIndicatorScale
    }
    
    /// Returns the frame of the loading indicator of the given button:
    private func buttonLoadingIndicatorFrame(_ button: NT_Button) -> CGFloat? {
        button.loadingIndicatorFrame
    }
    
    /// Returns the vertical padding of the given button:
    private func buttonVerticalPadding(_ button: NT_Button) -> Double {
        button.verticalPadding
    }
    
    /// Returns the horizontal padding of the given button:
    private func buttonHorizontalPadding(_ button: NT_Button) -> Double {
        button.horizontalPadding
    }
    
    /// Returns a 'Bool' value indicating whether or not the given button should take the full available width:
    private func isButtonFullWidth(_ button: NT_Button) -> Bool {
        button.isFullWidth
    }
    
    /// Returns the alignment of the given button:
    private func buttonAlignment(_ button: NT_Button) -> Alignment {
        button.alignment
    }
    
    /// Returns a 'Bool' value indicating whether or not the background of the given button should be shown at all:
    private func isShowingButtonBackground(_ button: NT_Button) -> Bool {
        button.isShowingBackground
    }
    
    /// Returns the color of the background of the given button:
    private func buttonBackgroundColor(_ button: NT_Button) -> Color {
        button.backgroundColor
    }
    
    /// Returns the starting color of the gradient of the background of the given button:
    private func buttonBackgroundGradientStart(_ button: NT_Button) -> Color {
        button.backgroundGradientStart
    }
    
    /// Returns the ending color of the gradient of the background of the given button:
    private func buttonBackgroundGradientEnd(_ button: NT_Button) -> Color {
        button.backgroundGradientEnd
    }
    
    /// Returns a 'Bool' value indicating whether or not the color of the background of the given button should have a gradient applied to it:
    private func isButtonBackgroundColorGradient(_ button: NT_Button) -> Bool {
        button.isBackgroundColorGradient
    }
    
    /// Returns the radius of the rounded corners of the given button:
    private func buttonCornerRadius(_ button: NT_Button) -> Double {
        button.cornerRadius
    }
    
    /// Returns the style of the rounded corners of the given button:
    private func buttonCornerStyle(_ button: NT_Button) -> RoundedCornerStyle {
        button.cornerStyle
    }
    
    /// Returns the role of the given button if applicable:
    private func buttonRole(_ button: NT_Button) -> ButtonRole? {
        button.role
    }
    
    /// Returns a 'Bool' value indicating whether or not the given button is disabled:
    private func isButtonDisabled(_ button: NT_Button) -> Bool {
        button.isDisabled
    }
    
    /// Returns the keyboard shortcut of the given button:
    private func buttonKeyboardShortcut(_ button: NT_Button) -> KeyboardShortcut? {
        button.keyboardShortcut
    }
    
    /// Returns the action of the given button:
    private func buttonAction(_ button: NT_Button) -> (() -> ())? {
        button.action
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        BannerView(
            isShowing: true,
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
            iconBorderColor: .blue,
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
            isShowingDismissButton: true,
            dismissButtonTitle: "Dismiss",
            isDismissButtonTitleLocalized: true,
            dismissButtonIcon: Icons.xmark,
            dismissButtonIconSymbolVariant: .fill,
            dismissButtonFont: .headline,
            dismissButtonColor: .init(.tertiaryLabel),
            dismissFrame: 24,
            alignment: .horizontal,
            verticalAlignment: .top,
            horizontalAlignment: .leading,
            spacing: 12,
            buttons: [
                .init(
                    id: "Try.For.Free",
                    title: "Try for Free",
                    isTitleLocalized: true,
                    titleFont: .subheadline.bold(),
                    titleTextCase: .none,
                    titleAlignment: .center,
                    titleColor: .white,
                    titleGradientStart: .blueGradientStart,
                    titleGradientEnd: .blueGradientEnd,
                    isTitleColorGradient: false,
                    icon: Icons.mailStack,
                    iconSymbolVariant: .fill,
                    iconFont: .subheadline.bold(),
                    iconColor: .white,
                    iconGradientStart: .blueGradientStart,
                    iconGradientEnd: .blueGradientEnd,
                    isIconColorGradient: false,
                    style: .titleOnly,
                    isLoading: false,
                    loadingIndicatorColor: .white,
                    loadingIndicatorScale: 1,
                    loadingIndicatorFrame: nil,
                    verticalPadding: 8,
                    horizontalPadding: 8,
                    isFullWidth: true,
                    alignment: .center,
                    isShowingBackground: true,
                    backgroundColor: .accent,
                    backgroundGradientStart: .blueGradientStart,
                    backgroundGradientEnd: .blueGradientEnd,
                    isBackgroundColorGradient: true,
                    cornerRadius: 10,
                    cornerStyle: .continuous,
                    role: nil,
                    isDisabled: false,
                    keyboardShortcut: nil,
                    action: {  }
                )
            ],
            buttonsVerticalAlignment: .center,
            buttonsHorizontalAlignment: .center,
            buttonsAlignment: .vertical,
            buttonsSpacing: 8,
            verticalPadding: 12,
            horizontalPadding: 12,
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
