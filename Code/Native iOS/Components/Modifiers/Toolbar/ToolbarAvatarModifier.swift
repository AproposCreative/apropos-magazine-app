//
//  ToolbarAvatarModifier.swift
//  Native
//

import SwiftUI

struct ToolbarAvatarModifier: ViewModifier {
    
    // MARK: - Private properties:
    
    /// 'Bool' value indicating whether or not the avatar should be shown at all:
    private let isShowing: Bool
    
    /// An actual type of the avatar:
    private let type: NT_AvatarType
    
    /// Initials of the avatar to display:
    private let initials: String
    
    /// Font of the initials of the avatar:
    private let initialsFont: Font
    
    /// Color of the initials of the avatar:
    private let initialsColor: Color
    
    /// Starting color of the gradient of the initials of the avatar if applicable:
    private let initialsGradientStart: Color
    
    /// Ending color of the gradient of the initials of the avatar if applicable:
    private let initialsGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the initials of the avatar should have a gradient applied to it:
    private let isInitialsColorGradient: Bool
    
    /// Icon of the avatar to display:
    private let icon: String
    
    /// Symbol variant of the icon of the avatar:
    private let iconSymbolVariant: SymbolVariants
    
    /// Font of the icon of the avatar:
    private let iconFont: Font
    
    /// Color of the icon of the avatar:
    private let iconColor: Color
    
    /// Starting color of the gradient of the icon of the avatar if applicable:
    private let iconGradientStart: Color
    
    /// Ending color of the gradient of the icon of the avatar if applicable:
    private let iconGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the icon of the avatar should have a gradient applied to it:
    private let isIconColorGradient: Bool
    
    /// Image of the avatar to display:
    private let image: Image
    
    /// Color of the avatar:
    private let color: Color
    
    /// Starting color of the gradient of the avatar if applicable:
    private let gradientStart: Color
    
    /// Ending color of the gradient of the avatar if applicable:
    private let gradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the avatar should have a gradient applied to it:
    private let isGradient: Bool
    
    /// Size of the frame of the avatar:
    private let frame: Double
    
    /// Radius of the rounded corners of the avatar:
    private let cornerRadius: Double
    
    /// Style of the rounded corners of the avatar:
    private let cornerStyle: RoundedCornerStyle
    
    /// 'Bool' value indicating whether or not the indicator of the avatar should be shown at all:
    private let isShowingIndicator: Bool
    
    /// Size of the frame of the indicator of the avatar:
    private let indicatorFrame: Double
    
    /// Color of the border of the indicator of the avatar:
    private let indicatorBorderColor: Color
    
    /// Width of the border of the indicator of the avatar:
    private let indicatorBorderWidth: Double
    
    /// Accessibility label of the indicator of the avatar if applicable:
    private let indicatorAccessibilityLabel: String
    
    /// 'Bool' value indicating whether or not the accessibility label of the indicator should be localized:
    private let isIndicatorAccessibilityLabelLocalized: Bool
    
    /// Alignment of the indicator of the avatar:
    private let indicatorAlignment: Alignment
    
    /// Placement of the avatar in the toolbar:
    private let placement: ToolbarItemPlacement
    
    /// Action that gets called when the avatar was tapped on if applicable:
    private let action: (() -> ())?
    
    init(
        isShowing: Bool,
        type: NT_AvatarType,
        initials: String,
        initialsFont: Font,
        initialsColor: Color,
        initialsGradientStart: Color,
        initialsGradientEnd: Color,
        isInitialsColorGradient: Bool = false,
        icon: String,
        iconSymbolVariant: SymbolVariants,
        iconFont: Font,
        iconColor: Color,
        iconGradientStart: Color,
        iconGradientEnd: Color,
        isIconColorGradient: Bool,
        image: Image,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color,
        isGradient: Bool,
        frame: Double,
        cornerRadius: Double,
        cornerStyle: RoundedCornerStyle,
        isShowingIndicator: Bool,
        indicatorFrame: Double,
        indicatorBorderColor: Color,
        indicatorBorderWidth: Double,
        indicatorAccessibilityLabel: String,
        isIndicatorAccessibilityLabelLocalized: Bool,
        indicatorAlignment: Alignment,
        placement: ToolbarItemPlacement,
        action: (() -> ())?
    ) {
        
        /// Properties initialization:
        self.isShowing = isShowing
        self.type = type
        self.initials = initials
        self.initialsFont = initialsFont
        self.initialsColor = initialsColor
        self.initialsGradientStart = initialsGradientStart
        self.initialsGradientEnd = initialsGradientEnd
        self.isInitialsColorGradient = isInitialsColorGradient
        self.icon = icon
        self.iconSymbolVariant = iconSymbolVariant
        self.iconFont = iconFont
        self.iconColor = iconColor
        self.iconGradientStart = iconGradientStart
        self.iconGradientEnd = iconGradientEnd
        self.isIconColorGradient = isIconColorGradient
        self.image = image
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.isGradient = isGradient
        self.frame = frame
        self.cornerRadius = cornerRadius
        self.cornerStyle = cornerStyle
        self.isShowingIndicator = isShowingIndicator
        self.indicatorFrame = indicatorFrame
        self.indicatorBorderColor = indicatorBorderColor
        self.indicatorBorderWidth = indicatorBorderWidth
        self.indicatorAccessibilityLabel = indicatorAccessibilityLabel
        self.isIndicatorAccessibilityLabelLocalized = isIndicatorAccessibilityLabelLocalized
        self.indicatorAlignment = indicatorAlignment
        self.placement = placement
        self.action = action
    }
    
    // MARK: - View:
    
    func body(content: Content) -> some View {
        if isShowing {
            toolbar(content)
        }
    }
}

// MARK: - Toolbar:

extension ToolbarAvatarModifier {
    private func toolbar(_ content: Content) -> some View {
        content
            .toolbar {
                toolbarContent
            }
    }
    
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: placement) {
            avatar
        }
    }
}

// MARK: - Avatar:

extension ToolbarAvatarModifier {
    private var avatar: some View {
        Button {
            action?()
        } label: {
            avatarLabel
        }
    }
    
    private var avatarLabel: some View {
        AvatarView(
            type: type,
            initials: initials,
            initialsFont: initialsFont,
            initialsColor: initialsColor,
            initialsGradientStart: initialsGradientStart,
            initialsGradientEnd: initialsGradientEnd,
            isInitialsColorGradient: isInitialsColorGradient,
            icon: icon,
            iconSymbolVariant: iconSymbolVariant,
            iconFont: iconFont,
            iconColor: iconColor,
            iconGradientStart: iconGradientStart,
            iconGradientEnd: iconGradientEnd,
            isIconColorGradient: isIconColorGradient,
            image: image,
            color: color,
            gradientStart: gradientStart,
            gradientEnd: gradientEnd,
            isGradient: isGradient,
            frame: frame,
            cornerRadius: cornerRadius,
            cornerStyle: cornerStyle,
            isShowingIndicator: isShowingIndicator,
            indicatorFrame: indicatorFrame,
            indicatorBorderColor: indicatorBorderColor,
            indicatorBorderWidth: indicatorBorderWidth,
            indicatorAccessibilityLabel: indicatorAccessibilityLabel,
            isIndicatorAccessibilityLabelLocalized: isIndicatorAccessibilityLabelLocalized,
            indicatorAlignment: indicatorAlignment
        )
    }
}

// MARK: - Modifier:

extension View {
    
    // MARK: - Functions:
    
    /// Returns the modifier that adds the avatar to the toolbar of the view:
    func toolbarAvatar(
        isShowing: Bool = true,
        type: NT_AvatarType = .initials,
        initials: String = "AL",
        initialsFont: Font = .system(
            size: 15,
            weight: .bold,
            design: .default
        ),
        initialsColor: Color = .white,
        initialsGradientStart: Color = .blueGradientStart,
        initialsGradientEnd: Color = .blueGradientEnd,
        isInitialsColorGradient: Bool = false,
        icon: String = Icons.person,
        iconSymbolVariant: SymbolVariants = .fill,
        iconFont: Font = .system(
            size: 15,
            weight: .bold,
            design: .default
        ),
        iconColor: Color = .white,
        iconGradientStart: Color = .blueGradientStart,
        iconGradientEnd: Color = .blueGradientEnd,
        isIconColorGradient: Bool = false,
        image: Image = .init(.account1),
        color: Color = .accent,
        gradientStart: Color = .blueGradientStart,
        gradientEnd: Color = .blueGradientEnd,
        isGradient: Bool = true,
        frame: Double = 36,
        cornerRadius: Double = 18,
        cornerStyle: RoundedCornerStyle = .continuous,
        isShowingIndicator: Bool = true,
        indicatorFrame: Double = 10,
        indicatorBorderColor: Color = .init(.systemBackground),
        indicatorBorderWidth: Double = 2,
        indicatorAccessibilityLabel: String = "",
        isIndicatorAccessibilityLabelLocalized: Bool = true,
        indicatorAlignment: Alignment = .topTrailing,
        placement: ToolbarItemPlacement = .confirmationAction,
        action: (() -> ())? = nil
    ) -> some View {
        modifier(
            ToolbarAvatarModifier(
                isShowing: isShowing,
                type: type,
                initials: initials,
                initialsFont: initialsFont,
                initialsColor: initialsColor,
                initialsGradientStart: initialsGradientStart,
                initialsGradientEnd: initialsGradientEnd,
                icon: icon,
                iconSymbolVariant: iconSymbolVariant,
                iconFont: iconFont,
                iconColor: iconColor,
                iconGradientStart: iconGradientStart,
                iconGradientEnd: iconGradientEnd,
                isIconColorGradient: isIconColorGradient,
                image: image,
                color: color,
                gradientStart: gradientStart,
                gradientEnd: gradientEnd,
                isGradient: isGradient,
                frame: frame,
                cornerRadius: cornerRadius,
                cornerStyle: cornerStyle,
                isShowingIndicator: isShowingIndicator,
                indicatorFrame: indicatorFrame,
                indicatorBorderColor: indicatorBorderColor,
                indicatorBorderWidth: indicatorBorderWidth,
                indicatorAccessibilityLabel: indicatorAccessibilityLabel,
                isIndicatorAccessibilityLabelLocalized: isIndicatorAccessibilityLabelLocalized,
                indicatorAlignment: indicatorAlignment,
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
        .toolbarAvatar(
            isShowing: true,
            type: .initials,
            initials: "AL",
            initialsFont: .system(
                size: 15,
                weight: .bold,
                design: .default
            ),
            initialsColor: .white,
            initialsGradientStart: .blueGradientStart,
            initialsGradientEnd: .blueGradientEnd,
            isInitialsColorGradient: false,
            icon: Icons.person,
            iconSymbolVariant: .fill,
            iconFont: .system(
                size: 15,
                weight: .bold,
                design: .default
            ),
            iconColor: .white,
            iconGradientStart: .blueGradientStart,
            iconGradientEnd: .blueGradientEnd,
            isIconColorGradient: false,
            image: .init(.account1),
            color: .accent,
            gradientStart: .blueGradientStart,
            gradientEnd: .blueGradientEnd,
            isGradient: true,
            frame: 36,
            cornerRadius: 18,
            cornerStyle: .continuous,
            isShowingIndicator: true,
            indicatorFrame: 10,
            indicatorBorderColor: .init(.systemBackground),
            indicatorBorderWidth: 2,
            indicatorAccessibilityLabel: "",
            isIndicatorAccessibilityLabelLocalized: true,
            indicatorAlignment: .topTrailing,
            placement: .confirmationAction
        ) {
            
        }
        .navigationStack()
}
