//
//  AvatarView.swift
//  Native
//

import SwiftUI

struct AvatarView: View {
    
    // MARK: - Private properties:
    
    /// An actual type of the avatar:
    private let type: NT_AvatarType
    
    /// Initials of the avatar to display:
    private let initials: String
    
    /// Font of the initials:
    private let initialsFont: Font
    
    /// Color of the initials:
    private let initialsColor: Color
    
    /// Starting color of the gradient of the initials if applicable:
    private let initialsGradientStart: Color
    
    /// Ending color of the gradient of the initials if applicable:
    private let initialsGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the initials should have a gradient applied to it:
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
    
    /// Color of the view:
    private let color: Color
    
    /// Starting color of the gradient of the view if applicable:
    private let gradientStart: Color
    
    /// Ending color of the gradient of the view if applicable:
    private let gradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the view should have a gradient applied to it:
    private let isGradient: Bool
    
    /// Size of the frame of the view:
    private let frame: Double
    
    /// Radius of the rounded corners of the view:
    private let cornerRadius: Double
    
    /// Style of the rounded corners of the view:
    private let cornerStyle: RoundedCornerStyle
    
    /// 'Bool' value indicating whether or not the indicator should be shown at all:
    private let isShowingIndicator: Bool
    
    /// Size of the frame of the indicator:
    private let indicatorFrame: Double
    
    /// Color of the border of the indicator:
    private let indicatorBorderColor: Color
    
    /// Width of the border of the indicator:
    private let indicatorBorderWidth: Double
    
    /// Accessibility label of the indicator of the avatar if applicable:
    private let indicatorAccessibilityLabel: String
    
    /// 'Bool' value indicating whether or not the accessibility label of the indicator should be localized:
    private let isIndicatorAccessibilityLabelLocalized: Bool
    
    /// Alignment of the indicator:
    private let indicatorAlignment: Alignment
    
    init(
        type: NT_AvatarType = .initials,
        initials: String = "AL",
        initialsFont: Font = .subheadline.weight(.bold),
        initialsColor: Color = .white,
        initialsGradientStart: Color = .blueGradientStart,
        initialsGradientEnd: Color = .blueGradientEnd,
        isInitialsColorGradient: Bool = false,
        icon: String = Icons.person,
        iconSymbolVariant: SymbolVariants = .fill,
        iconFont: Font = .subheadline.weight(.bold),
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
        indicatorAlignment: Alignment = .topTrailing
    ) {
        
        /// Properties initialization:
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
    }
    
    // MARK: - Private computed properties:
    
    /// Value of the accessibility label of the indicator of the avatar if applicable:
    private var indicatorAccessibilityLabelValue: Text {
        isIndicatorAccessibilityLabelLocalized
        ? .init(.init(indicatorAccessibilityLabel))
        : .init(indicatorAccessibilityLabel)
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .overlay(alignment: indicatorAlignment) {
                indicator
            }
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Item:

private extension AvatarView {
    @ViewBuilder
    private var item: some View {
        switch type {
        case .initials: initialsContent
        case .icon: iconContent
        case .image: imageContent
        }
    }
}

// MARK: - Initials:

private extension AvatarView {
    private var initialsContent: some View {
        Text(initials)
            .font(initialsFont)
            .multilineTextAlignment(.center)
            .foregroundGradient(
                color: initialsColor,
                gradientStart: initialsGradientStart,
                gradientEnd: initialsGradientEnd,
                isGradient: isInitialsColorGradient
            )
            .frame(
                width: frame,
                height: frame,
                alignment: .center
            )
            .gradientBackground(
                color: color,
                gradientStart: gradientStart,
                gradientEnd: gradientEnd,
                isGradient: isGradient
            )
            .roundedCorners(
                cornerRadius: cornerRadius,
                cornerStyle: cornerStyle
            )
    }
}

// MARK: - Icon:

private extension AvatarView {
    private var iconContent: some View {
        Image(systemName: icon)
            .symbolVariant(iconSymbolVariant)
            .font(iconFont)
            .foregroundGradient(
                color: initialsColor,
                gradientStart: initialsGradientStart,
                gradientEnd: initialsGradientEnd,
                isGradient: isInitialsColorGradient
            )
            .frame(
                width: frame,
                height: frame,
                alignment: .center
            )
            .gradientBackground(
                color: color,
                gradientStart: gradientStart,
                gradientEnd: gradientEnd,
                isGradient: isGradient
            )
            .roundedCorners(
                cornerRadius: cornerRadius,
                cornerStyle: cornerStyle
            )
    }
}

// MARK: - Image:

private extension AvatarView {
    private var imageContent: some View {
        image
            .resizable()
            .scaledToFill()
            .frame(
                width: frame,
                height: frame,
                alignment: .center
            )
            .roundedCorners(
                cornerRadius: cornerRadius,
                cornerStyle: cornerStyle
            )
    }
}

// MARK: - Indicator:

private extension AvatarView {
    @ViewBuilder
    private var indicator: some View {
        if isShowingIndicator {
            indicatorContent
        }
    }
    
    private var indicatorContent: some View {
        Circle()
            .gradientFill(
                color: color,
                gradientStart: gradientStart,
                gradientEnd: gradientEnd,
                isGradient: isGradient
            )
            .frame(
                width: indicatorFrame,
                height: indicatorFrame,
                alignment: .center
            )
            .overlay(indicatorStroke)
            .accessibilityLabel(indicatorAccessibilityLabelValue)
    }
    
    private var indicatorStroke: some View {
        Circle()
            .stroke(
                indicatorBorderColor,
                lineWidth: indicatorBorderWidth
            )
            .frame(
                width: indicatorFrame,
                height: indicatorFrame,
                alignment: .center
            )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        AvatarView(
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
            indicatorAlignment: .topTrailing
        )
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .contentBackground()
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
