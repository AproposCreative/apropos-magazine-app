//
//  ToolbarButtonModifier.swift
//  Native
//

import SwiftUI

struct ToolbarButtonModifier: ViewModifier {
    
    // MARK: - Private properties:
    
    /// 'Bool' value indicating whether or not the button should be shown at all:
    private let isShowing: Bool
    
    /// Title of the button:
    private let title: String
    
    /// 'Bool' value indicating whether or nor the title of the button should be localized:
    private let isTitleLocalized: Bool
    
    /// Icon of the button to display (If applicable which depends on the style of the button):
    private let icon: String
    
    /// Symbol variant of the icon of the button:
    private let iconSymbolVariant: SymbolVariants
    
    /// Font of the button:
    private let font: Font
    
    /// Color of the button:
    private let color: Color?
    
    /// Starting color of the gradient of the color of the button if applicable:
    private let gradientStart: Color
    
    /// Ending color of the gradient of the color of the button if applicable:
    private let gradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the button should have a gradient applied to it:
    private let isGradient: Bool
    
    /// Style of the label of the button:
    private let style: NT_LabelStyle
    
    /// 'Bool' value indicating whether or not the loading indicator should be shown at all:
    private let isLoading: Bool
    
    /// Color of the loading indicator:
    private let loadingIndicatorColor: Color
    
    /// Role of the button if applicable:
    private let role: ButtonRole?
    
    /// 'Bool' value indicating whether or not the button should be disabled:
    private let isDisabled: Bool
    
    /// Keyboard shortcut to use for the button if applicable:
    private let keyboardShortcut: KeyboardShortcut?
    
    /// Placement of the button in the toolbar:
    private let placement: ToolbarItemPlacement
    
    /// Action of the button if applicable:
    private let action: (() -> ())?
    
    init(
        isShowing: Bool,
        title: String,
        isTitleLocalized: Bool,
        icon: String,
        iconSymbolVariant: SymbolVariants,
        font: Font,
        color: Color?,
        gradientStart: Color,
        gradientEnd: Color,
        isGradient: Bool,
        style: NT_LabelStyle,
        isLoading: Bool,
        loadingIndicatorColor: Color,
        role: ButtonRole?,
        isDisabled: Bool,
        keyboardShortcut: KeyboardShortcut?,
        placement: ToolbarItemPlacement,
        action: (() -> ())?
    ) {
        
        /// Properties initialization:
        self.isShowing = isShowing
        self.title = title
        self.isTitleLocalized = isTitleLocalized
        self.icon = icon
        self.iconSymbolVariant = iconSymbolVariant
        self.font = font
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.isGradient = isGradient
        self.style = style
        self.isLoading = isLoading
        self.loadingIndicatorColor = loadingIndicatorColor
        self.role = role
        self.isDisabled = isDisabled
        self.placement = placement
        self.keyboardShortcut = keyboardShortcut
        self.action = action
    }
    
    // MARK: - View:
    
    func body(content: Content) -> some View {
        if isShowing {
            self.content(content)
        } else {
            content
        }
    }
    
    private func content(_ content: Content) -> some View {
        content
            .toolbar {
                toolbar
            }
    }
}

// MARK: - Toolbar:

extension ToolbarButtonModifier {
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: placement) {
            button
        }
    }
}

// MARK: - Button:

extension ToolbarButtonModifier {
    private var button: some View {
        buttonContent
            .buttonStyle(.plain)
    }
    
    private var buttonContent: some View {
        ButtonView(
            title: title,
            isTitleLocalized: isTitleLocalized,
            titleFont: font,
            titleColor: color,
            titleGradientStart: gradientStart,
            titleGradientEnd: gradientEnd,
            isTitleColorGradient: isGradient,
            icon: icon,
            iconSymbolVariant: iconSymbolVariant,
            iconFont: font,
            iconColor: color,
            iconGradientStart: gradientStart,
            iconGradientEnd: gradientEnd,
            isIconColorGradient: isGradient,
            style: style,
            isLoading: isLoading,
            loadingIndicatorColor: loadingIndicatorColor,
            verticalPadding: 0,
            horizontalPadding: 0,
            isFullWidth: false,
            isShowingBackground: false,
            backgroundColor: .clear,
            backgroundGradientStart: .clear,
            backgroundGradientEnd: .clear,
            isBackgroundColorGradient: false,
            cornerRadius: 0,
            role: role,
            isDisabled: isDisabled,
            keyboardShortcut: keyboardShortcut,
            action: action
        )
    }
}

// MARK: - Modifier:

extension View {
    
    // MARK: - Functions:
    
    /// Returns the modifier that adds the button to the toolbar of the view:
    func toolbarButton(
        isShowing: Bool = true,
        title: String,
        isTitleLocalized: Bool = true,
        icon: String = Icons.mailStack,
        iconSymbolVariant: SymbolVariants = .fill,
        font: Font = .headline,
        color: Color? = .accentColor,
        gradientStart: Color = .blueGradientStart,
        gradientEnd: Color = .blueGradientEnd,
        isGradient: Bool = false,
        style: NT_LabelStyle = .titleOnly,
        isLoading: Bool = false,
        loadingIndicatorColor: Color = .secondary,
        role: ButtonRole? = nil,
        isDisabled: Bool = false,
        keyboardShortcut: KeyboardShortcut? = nil,
        placement: ToolbarItemPlacement = .confirmationAction,
        action: (() -> ())? = nil
    ) -> some View {
        modifier(
            ToolbarButtonModifier(
                isShowing: isShowing,
                title: title,
                isTitleLocalized: isTitleLocalized,
                icon: icon,
                iconSymbolVariant: iconSymbolVariant,
                font: font,
                color: color,
                gradientStart: gradientStart,
                gradientEnd: gradientEnd,
                isGradient: isGradient,
                style: style,
                isLoading: isLoading,
                loadingIndicatorColor: loadingIndicatorColor,
                role: role,
                isDisabled: isDisabled,
                keyboardShortcut: keyboardShortcut,
                placement: placement,
                action: action
            )
        )
    }
}

// MARK: - Preview:

#Preview {
    Text("Preview")
        .font(.body)
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .padding()
        .toolbarButton(
            isShowing: true,
            title: "Done",
            isTitleLocalized: true,
            icon: Icons.mailStack,
            iconSymbolVariant: .fill,
            font: .headline,
            color: .accent,
            gradientStart: .blueGradientStart,
            gradientEnd: .blueGradientEnd,
            isGradient: false,
            style: .titleOnly,
            isLoading: false,
            role: nil,
            isDisabled: false,
            keyboardShortcut: nil,
            placement: .confirmationAction
        ) {
            
        }
        .navigationStack()
}
