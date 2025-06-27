//
//  NT_Button.swift
//  Native
//

import SwiftUI

struct NT_Button {
    
    // MARK: - Properties:
    
    /// Identifier of the button:
    let id: String
    
    /// Title of the button:
    let title: String
    
    /// 'Bool' value indicating whether or not the title of the button should be localized:
    let isTitleLocalized: Bool
    
    /// Font of the title of the button:
    let titleFont: Font
    
    /// Text case of the title of the button:
    let titleTextCase: Text.Case?
    
    /// Alignment of the title of the button:
    let titleAlignment: TextAlignment
    
    /// Color of the title of the button:
    let titleColor: Color?
    
    /// Starting color of the gradient of the color of the title of the button if applicable:
    let titleGradientStart: Color
    
    /// Ending color of the gradient of the color of the title of the button if applicable:
    let titleGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the title of the button should have a gradient applied to it:
    let isTitleColorGradient: Bool
    
    /// Icon of the button to display (If applicable which depends on the style of the button):
    let icon: String
    
    /// Symbol variant of the icon of the button:
    let iconSymbolVariant: SymbolVariants
    
    /// Font of the icon of the button:
    let iconFont: Font
    
    /// Color of the icon of the button:
    let iconColor: Color?
    
    /// Starting color of the gradient of the color of the icon of the button if applicable:
    let iconGradientStart: Color
    
    /// Ending color of the gradient of the color of the icon of the button if applicable:
    let iconGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the icon of the button should have a gradient applied to it:
    let isIconColorGradient: Bool
    
    /// Style of the label of the button:
    let style: NT_LabelStyle
    
    /// 'Bool' value indicating whether or not the loading indicator should be shown at all:
    let isLoading: Bool
    
    /// Color of the loading indicator:
    let loadingIndicatorColor: Color
    
    /// Scale of the loading indicator ('1' is the default scale, anything more will increase the size of the indicator, anything less will decrease its size):
    let loadingIndicatorScale: Double
    
    /// Size of the frame of the loading indicator (Can simply be 'nil' if needed):
    let loadingIndicatorFrame: CGFloat?
    
    /// Vertical padding of the button:
    let verticalPadding: Double
    
    /// Horizontal padding of the button:
    let horizontalPadding: Double
    
    /// 'Bool' value indicating whether or not the button should take the full available width:
    let isFullWidth: Bool
    
    /// Alignment of the button:
    let alignment: Alignment
    
    /// 'Bool' value indicating whether or not the background of the button should be shown at all:
    let isShowingBackground: Bool
    
    /// Color of the background of the button:
    let backgroundColor: Color
    
    /// Starting color of the gradient of the background of the button if applicable:
    let backgroundGradientStart: Color
    
    /// Ending color of the gradient of the background of the button if applicable:
    let backgroundGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the background of the button should have a gradient applied to it:
    let isBackgroundColorGradient: Bool
    
    /// Radius of the rounded corners of the button.
    let cornerRadius: Double
    
    /// Style of the rounded corners of the button:
    let cornerStyle: RoundedCornerStyle
    
    /// Role of the button if applicable:
    let role: ButtonRole?
    
    /// 'Bool' value indicating whether or not the button should be disabled:
    let isDisabled: Bool
    
    /// Keyboard shortcut to use for the button if applicable:
    let keyboardShortcut: KeyboardShortcut?
    
    /// An actual action of the button if applicable:
    let action: (() -> ())?
    
    init(
        id: String,
        title: String,
        isTitleLocalized: Bool,
        titleFont: Font,
        titleTextCase: Text.Case?,
        titleAlignment: TextAlignment,
        titleColor: Color?,
        titleGradientStart: Color,
        titleGradientEnd: Color,
        isTitleColorGradient: Bool,
        icon: String,
        iconSymbolVariant: SymbolVariants,
        iconFont: Font,
        iconColor: Color?,
        iconGradientStart: Color,
        iconGradientEnd: Color,
        isIconColorGradient: Bool,
        style: NT_LabelStyle,
        isLoading: Bool,
        loadingIndicatorColor: Color,
        loadingIndicatorScale: Double,
        loadingIndicatorFrame: CGFloat?,
        verticalPadding: Double,
        horizontalPadding: Double,
        isFullWidth: Bool,
        alignment: Alignment,
        isShowingBackground: Bool,
        backgroundColor: Color,
        backgroundGradientStart: Color,
        backgroundGradientEnd: Color,
        isBackgroundColorGradient: Bool,
        cornerRadius: Double,
        cornerStyle: RoundedCornerStyle,
        role: ButtonRole?,
        isDisabled: Bool,
        keyboardShortcut: KeyboardShortcut?,
        action: (() -> ())?
    ) {
        
        /// Properties initialization:
        self.id = id
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
}

// MARK: - Identifiable:

extension NT_Button: Identifiable {  }

// MARK: - Equatable:

extension NT_Button: Equatable {
    
    // MARK: - Functions:
    
    /// Returns a 'Bool' value indicating whether or not the arguments on both sides are equal:
    static func == (
        lhs: NT_Button,
        rhs: NT_Button
    ) -> Bool {
        lhs.id == rhs.id
        && lhs.title == rhs.title
        && lhs.isTitleLocalized == rhs.isTitleLocalized
        && lhs.titleFont == rhs.titleFont
        && lhs.titleTextCase == rhs.titleTextCase
        && lhs.titleAlignment == rhs.titleAlignment
        && lhs.titleColor == rhs.titleColor
        && lhs.titleGradientStart == rhs.titleGradientStart
        && lhs.titleGradientEnd == rhs.titleGradientEnd
        && lhs.isTitleColorGradient == rhs.isTitleColorGradient
        && lhs.icon == rhs.icon
        && lhs.iconSymbolVariant == rhs.iconSymbolVariant
        && lhs.iconFont == rhs.iconFont
        && lhs.iconColor == rhs.iconColor
        && lhs.iconGradientStart == rhs.iconGradientStart
        && lhs.iconGradientEnd == rhs.iconGradientEnd
        && lhs.isIconColorGradient == rhs.isIconColorGradient
        && lhs.style == rhs.style
        && lhs.isLoading == rhs.isLoading
        && lhs.loadingIndicatorColor == rhs.loadingIndicatorColor
        && lhs.loadingIndicatorScale == rhs.loadingIndicatorScale
        && lhs.loadingIndicatorFrame == rhs.loadingIndicatorFrame
        && lhs.verticalPadding == rhs.verticalPadding
        && lhs.horizontalPadding == rhs.horizontalPadding
        && lhs.isFullWidth == rhs.isFullWidth
        && lhs.alignment == rhs.alignment
        && lhs.isShowingBackground == rhs.isShowingBackground
        && lhs.backgroundColor == rhs.backgroundColor
        && lhs.backgroundGradientStart == rhs.backgroundGradientStart
        && lhs.backgroundGradientEnd == rhs.backgroundGradientEnd
        && lhs.isBackgroundColorGradient == rhs.isBackgroundColorGradient
        && lhs.cornerRadius == rhs.cornerRadius
        && lhs.cornerStyle == rhs.cornerStyle
        && lhs.role == rhs.role
        && lhs.isDisabled == rhs.isDisabled
        && lhs.keyboardShortcut == rhs.keyboardShortcut
    }
}

// MARK: - Hashable:

extension NT_Button: Hashable {
    
    // MARK: - Functions:
    
    /// Hashes the values of the button using the given hasher:
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(isTitleLocalized)
        hasher.combine(titleFont)
        hasher.combine(titleTextCase)
        hasher.combine(titleAlignment)
        hasher.combine(titleColor)
        hasher.combine(titleGradientStart)
        hasher.combine(titleGradientEnd)
        hasher.combine(isTitleColorGradient)
        hasher.combine(icon)
        hasher.combine(iconSymbolVariant)
        hasher.combine(iconFont)
        hasher.combine(iconColor)
        hasher.combine(iconGradientStart)
        hasher.combine(iconGradientEnd)
        hasher.combine(isIconColorGradient)
        hasher.combine(style)
        hasher.combine(isLoading)
        hasher.combine(loadingIndicatorColor)
        hasher.combine(loadingIndicatorScale)
        hasher.combine(loadingIndicatorFrame)
        hasher.combine(verticalPadding)
        hasher.combine(horizontalPadding)
        hasher.combine(isFullWidth)
        hasher.combine(isShowingBackground)
        hasher.combine(backgroundColor)
        hasher.combine(backgroundGradientStart)
        hasher.combine(backgroundGradientEnd)
        hasher.combine(isBackgroundColorGradient)
        hasher.combine(cornerRadius)
        hasher.combine(cornerStyle)
        hasher.combine(isDisabled)
        hasher.combine(keyboardShortcut)
    }
}

// MARK: - Example:

extension NT_Button {
    
    // MARK: - Computed properties:
    
    /// An array of the example buttons:
    static var example: [NT_Button] {
        [
            .init(
                id: "Button.1",
                title: "Button - 1",
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
                keyboardShortcut: nil,
                action: {  }
            ),
            .init(
                id: "Button.2",
                title: "Button - 2",
                isTitleLocalized: true,
                titleFont: .headline,
                titleTextCase: .none,
                titleAlignment: .center,
                titleColor: .white,
                titleGradientStart: .blueGradientStart,
                titleGradientEnd: .blueGradientEnd,
                isTitleColorGradient: true,
                icon: Icons.mailStack,
                iconSymbolVariant: .fill,
                iconFont: .headline,
                iconColor: .white,
                iconGradientStart: .blueGradientStart,
                iconGradientEnd: .blueGradientEnd,
                isIconColorGradient: false,
                style: .titleOnly,
                isLoading: false,
                loadingIndicatorColor: .white,
                loadingIndicatorScale: 1,
                loadingIndicatorFrame: nil,
                verticalPadding: 12,
                horizontalPadding: 12,
                isFullWidth: true,
                alignment: .center,
                isShowingBackground: false,
                backgroundColor: .accent,
                backgroundGradientStart: .blueGradientStart,
                backgroundGradientEnd: .blueGradientEnd,
                isBackgroundColorGradient: true,
                cornerRadius: 14,
                cornerStyle: .continuous,
                role: nil,
                isDisabled: false,
                keyboardShortcut: nil,
                action: {  }
            )
        ]
    }
}
