//
//  ButtonView.swift
//  Native
//

import SwiftUI

struct ButtonView: View {
    
    // MARK: - Private properties:
    
    /// Title of the button:
    private let title: String
    
    /// 'Bool' value indicating whether or not the title of the button should be localized:
    private let isTitleLocalized: Bool
    
    /// Font of the title of the button:
    private let titleFont: Font
    
    /// Text case of the title of the button:
    private let titleTextCase: Text.Case?
    
    /// Alignment of the title of the button:
    private let titleAlignment: TextAlignment
    
    /// Color of the title of the button:
    private let titleColor: Color?
    
    /// Starting color of the gradient of the color of the title of the button if applicable:
    private let titleGradientStart: Color
    
    /// Ending color of the gradient of the color of the title of the button if applicable:
    private let titleGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the title of the button should have a gradient applied to it:
    private let isTitleColorGradient: Bool
    
    /// Icon of the button to display (If applicable which depends on the style of the button):
    private let icon: String
    
    /// Symbol variant of the icon of the button:
    private let iconSymbolVariant: SymbolVariants
    
    /// Font of the icon of the button:
    private let iconFont: Font
    
    /// Color of the icon of the button if applicable:
    private let iconColor: Color?
    
    /// Starting color of the gradient of the icon of the button if applicable:
    private let iconGradientStart: Color
    
    /// Ending color of the gradient of the icon of the button if applicable:
    private let iconGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the icon of the button should have a gradient applied to it:
    private let isIconColorGradient: Bool
    
    /// Size of the frame of the icon if applicable:
    private let iconFrame: CGFloat?
    
    /// Style of the label of the button:
    private let style: NT_LabelStyle
    
    /// 'Bool' value indicating whether or not the loading indicator should be shown at all:
    private let isLoading: Bool
    
    /// Color of the loading indicator:
    private let loadingIndicatorColor: Color
    
    /// Scale of the loading indicator ('1' is the default scale, anything more will increase the size of the indicator, anything less will decrease its size):
    private let loadingIndicatorScale: Double
    
    /// Frame of the loading indicator (Can simply be 'nil' if needed):
    private let loadingIndicatorFrame: CGFloat?
    
    /// Vertical padding of the button:
    private let verticalPadding: Double
    
    /// Horizontal padding of the button:
    private let horizontalPadding: Double
    
    /// 'Bool' value indicating whether or not the button should take the full available width:
    private let isFullWidth: Bool
    
    /// Alignment of the button:
    private let alignment: Alignment
    
    /// 'Bool' value indicating whether or not the background of the button should be shown at all:
    private let isShowingBackground: Bool
    
    /// Color of the background of the button:
    private let backgroundColor: Color
    
    /// Starting color of the gradient of the background of the button if applicable:
    private let backgroundGradientStart: Color
    
    /// Ending color of the gradient of the background of the button if applicable:
    private let backgroundGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the background of the button should have a gradient applied to it:
    private let isBackgroundColorGradient: Bool
    
    /// Radius of the rounded corners of the button.
    private let cornerRadius: Double
    
    /// Style of the rounded corners of the button:
    private let cornerStyle: RoundedCornerStyle
    
    /// Role of the button if applicable:
    private let role: ButtonRole?
    
    /// 'Bool' value indicating whether or not the button should be disabled:
    private let isDisabled: Bool
    
    /// Keyboard shortcut to use for the button if applicable:
    private let keyboardShortcut: KeyboardShortcut?
    
    /// An actual action of the button if applicable:
    private let action: (() -> ())?
    
    init(
        title: String,
        isTitleLocalized: Bool = true,
        titleFont: Font = .headline,
        titleTextCase: Text.Case? = .none,
        titleAlignment: TextAlignment = .center,
        titleColor: Color? = .white,
        titleGradientStart: Color = .blueGradientStart,
        titleGradientEnd: Color = .blueGradientEnd,
        isTitleColorGradient: Bool = false,
        icon: String = Icons.mailStack,
        iconSymbolVariant: SymbolVariants = .fill,
        iconFont: Font = .headline,
        iconColor: Color? = .white,
        iconGradientStart: Color = .blueGradientStart,
        iconGradientEnd: Color = .blueGradientEnd,
        isIconColorGradient: Bool = false,
        iconFrame: CGFloat? = nil,
        style: NT_LabelStyle = .titleOnly,
        isLoading: Bool = false,
        loadingIndicatorColor: Color = .white,
        loadingIndicatorScale: Double = 1,
        loadingIndicatorFrame: CGFloat? = nil,
        verticalPadding: Double = 12,
        horizontalPadding: Double = 12,
        isFullWidth: Bool = true,
        alignment: Alignment = .center,
        isShowingBackground: Bool = true,
        backgroundColor: Color = .accent,
        backgroundGradientStart: Color = .blueGradientStart,
        backgroundGradientEnd: Color = .blueGradientEnd,
        isBackgroundColorGradient: Bool = true,
        cornerRadius: Double = 14,
        cornerStyle: RoundedCornerStyle = .continuous,
        role: ButtonRole? = nil,
        isDisabled: Bool = false,
        keyboardShortcut: KeyboardShortcut? = nil,
        action: (() -> ())?
    ) {
        
        /// Properties initialization:
        self.title = title
        self.isTitleLocalized = isTitleLocalized
        self.titleFont = titleFont
        self.titleTextCase = titleTextCase
        self.titleAlignment = titleAlignment
        self.titleColor = titleColor
        self.titleGradientStart = titleGradientStart
        self.titleGradientEnd = titleGradientEnd
        self.isTitleColorGradient = isTitleColorGradient
        self.icon = icon
        self.iconSymbolVariant = iconSymbolVariant
        self.iconFont = iconFont
        self.iconColor = iconColor
        self.iconGradientStart = iconGradientStart
        self.iconGradientEnd = iconGradientEnd
        self.isIconColorGradient = isIconColorGradient
        self.iconFrame = iconFrame
        self.style = style
        self.isLoading = isLoading
        self.loadingIndicatorColor = loadingIndicatorColor
        self.loadingIndicatorScale = loadingIndicatorScale
        self.loadingIndicatorFrame = loadingIndicatorFrame
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
        self.isFullWidth = isFullWidth
        self.alignment = alignment
        self.isShowingBackground = isShowingBackground
        self.backgroundColor = backgroundColor
        self.backgroundGradientStart = backgroundGradientStart
        self.backgroundGradientEnd = backgroundGradientEnd
        self.isBackgroundColorGradient = isBackgroundColorGradient
        self.cornerRadius = cornerRadius
        self.cornerStyle = cornerStyle
        self.role = role
        self.isDisabled = isDisabled
        self.keyboardShortcut = keyboardShortcut
        self.action = action
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the button should actually be disabled:
    private var isDisabledValue: Bool {
        isDisabled || isLoading
    }
    
    /// Content of the color of the icon of the button:
    private var iconColorContent: Color? {
        if isShowingBackground {
            return iconColor
        } else {
            return iconColor?.opacity(opacity)
        }
    }
    
    /// Content of the starting color of the gradient of the icon of the button:
    private var iconGradientStartContent: Color {
        if isShowingBackground {
            return iconGradientStart
        } else {
            return iconGradientStart.opacity(opacity)
        }
    }
    
    /// Content of the ending color of the gradient of the icon of the button:
    private var iconGradientEndContent: Color {
        if isShowingBackground {
            return iconGradientEnd
        } else {
            return iconGradientEnd.opacity(opacity)
        }
    }
    
    /// Content of the color of the title of the button:
    private var titleColorContent: Color? {
        if isShowingBackground {
            return titleColor
        } else {
            return titleColor?.opacity(opacity)
        }
    }
    
    /// Content of the starting color of the gradient of the title of the button:
    private var titleGradientStartContent: Color {
        if isShowingBackground {
            return titleGradientStart
        } else {
            return titleGradientStart.opacity(opacity)
        }
    }
    
    /// Content of the ending color of the gradient of the title of the button:
    private var titleGradientEndContent: Color {
        if isShowingBackground {
            return titleGradientEnd
        } else {
            return titleGradientEnd.opacity(opacity)
        }
    }
    
    /// Content of the color of the background of the button:
    private var backgroundColorContent: Color {
        if isShowingBackground {
            return backgroundColor.opacity(opacity)
        } else {
            return .clear
        }
    }
    
    /// Content of the starting color of the gradient of the background of the button:
    private var backgroundGradientStartContent: Color {
        if isShowingBackground {
            return backgroundGradientStart.opacity(opacity)
        } else {
            return .clear
        }
    }
    
    /// Content of the ending color of the gradient of the background of the button:
    private var backgroundGradientEndContent: Color {
        if isShowingBackground {
            return backgroundGradientEnd.opacity(opacity)
        } else {
            return .clear
        }
    }
    
    /// Maximum width of the button based on whether or not it should take the full width if applicable:
    private var maxWidth: CGFloat? {
        isFullWidth ? .infinity : nil
    }
    
    /// Opacity of the button based on whether or not it's currently disabled:
    private var opacity: Double {
        isDisabledValue ? 0.5 : 1
    }
    
    /// Additional accessibility hint of the view that is needed to indicate whether or not the button is currently disabled:
    private var accessibilityHint: LocalizedStringKey {
        isDisabledValue ? "This button is currently disabled." : ""
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .disabled(isDisabledValue)
            .keyboardShortcut(keyboardShortcut)
            .accessibilityHint(accessibilityHint)
    }
}

// MARK: - Item:

private extension ButtonView {
    private var item: some View {
        Button(role: role) {
            action?()
        } label: {
            label
        }
    }
}

// MARK: - Label:

private extension ButtonView {
    @ViewBuilder
    private var label: some View {
        switch style {
        case .none: labelContent
        case .titleAndIcon: titleAndIcon
        case .titleOnly: titleOnlyLabel
        case .iconOnly: iconOnlyLabel
        }
    }
    
    private var titleAndIcon: some View {
        labelContent
            .labelStyle(.titleAndIcon)
    }
    
    private var titleOnlyLabel: some View {
        labelContent
            .labelStyle(.titleOnly)
    }
    
    private var iconOnlyLabel: some View {
        labelContent
            .labelStyle(.iconOnly)
    }
    
    private var labelContent: some View {
        labelItem
            .textCase(titleTextCase)
            .multilineTextAlignment(titleAlignment)
            .padding(
                .vertical,
                verticalPadding
            )
            .padding(
                .horizontal,
                horizontalPadding
            )
            .frame(
                maxWidth: maxWidth,
                alignment: alignment
            )
            .gradientBackground(
                color: backgroundColorContent,
                gradientStart: backgroundGradientStartContent,
                gradientEnd: backgroundGradientEndContent,
                isGradient: isBackgroundColorGradient
            )
            .roundedCorners(
                cornerRadius: cornerRadius,
                cornerStyle: cornerStyle
            )
    }
    
    @ViewBuilder
    private var labelItem: some View {
        if isLoading {
            loading
        } else {
            labelItemContent
        }
    }
    
    private var labelItemContent: some View {
        Label {
            titleContent
        } icon: {
            iconContent
        }
    }
    
    private var titleContent: some View {
        titleItem
            .font(titleFont)
            .foregroundGradient(
                color: titleColorContent,
                gradientStart: titleGradientStartContent,
                gradientEnd: titleGradientEndContent,
                isGradient: isTitleColorGradient
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
    
    private var iconContent: some View {
        Image(systemName: icon)
            .symbolVariant(iconSymbolVariant)
            .font(iconFont)
            .foregroundGradient(
                color: iconColorContent,
                gradientStart: iconGradientStartContent,
                gradientEnd: iconGradientEndContent,
                isGradient: isIconColorGradient
            )
            .frame(
                width: iconFrame,
                height: iconFrame,
                alignment: .center
            )
    }
    
    private var loading: some View {
        LoadingView(
            isShowing: isLoading,
            color: loadingIndicatorColor,
            scale: loadingIndicatorScale,
            frame: loadingIndicatorFrame
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        ButtonView(
            title: "Title",
            isTitleLocalized: true,
            titleFont: .headline,
            titleTextCase: .none,
            titleAlignment: .center,
            titleColor: .white,
            titleGradientStart: .blueGradientStart,
            titleGradientEnd: .blueGradientEnd,
            isTitleColorGradient: false,
            icon: Icons.mailStack,
            iconSymbolVariant: .fill,
            iconFont: .headline,
            iconColor: .white,
            iconGradientStart: .blueGradientStart,
            iconGradientEnd: .blueGradientEnd,
            isIconColorGradient: false,
            iconFrame: nil,
            style: .titleOnly,
            isLoading: false,
            loadingIndicatorColor: .white,
            loadingIndicatorScale: 1,
            loadingIndicatorFrame: nil,
            verticalPadding: 12,
            horizontalPadding: 12,
            isFullWidth: true,
            alignment: .center,
            isShowingBackground: true,
            backgroundColor: .accent,
            backgroundGradientStart: .blueGradientStart,
            backgroundGradientEnd: .blueGradientEnd,
            isBackgroundColorGradient: true,
            cornerRadius: 14,
            cornerStyle: .continuous,
            role: nil,
            isDisabled: false,
            keyboardShortcut: nil
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
