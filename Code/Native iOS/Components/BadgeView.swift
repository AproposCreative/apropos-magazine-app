//
//  BadgeView.swift
//  Native
//

import SwiftUI

struct BadgeView: View {
    
    // MARK: - Private properties:
    
    /// 'Bool' value indicating whether or not the icon of the badge should be shown at all:
    private let isShowingIcon: Bool
    
    /// An actual icon of the badge to display if applicable:
    private let icon: String
    
    /// Symbol variant of the icon of the badge if applicable (It could be '.fill', '.circle', etc.):
    private let iconSymbolVariant: SymbolVariants
    
    /// Color of the icon of the badge if applicable:
    private let iconColor: Color
    
    /// Starting color of the gradient of the icon of the badge if applicable:
    private let iconGradientStart: Color
    
    /// Ending color of the gradient of the icon of the badge if applicable:
    private let iconGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the icon of the badge should have a gradient applied to it if applicable:
    private let isIconColorGradient: Bool
    
    /// Title of the badge:
    private let title: String
    
    /// 'Bool' value indicating whether or not the title of the badge should be localized:
    private let isTitleLocalized: Bool
    
    /// Text case of the title of the badge:
    private let titleTextCase: Text.Case?
    
    /// Alignment of the title of the badge:
    private let titleAlignment: TextAlignment
    
    /// Color of the title of the badge:
    private let titleColor: Color
    
    /// Starting color of the gradient of the title of the badge if applicable:
    private let titleGradientStart: Color
    
    /// Ending color of the gradient of the title of the badge if applicable:
    private let titleGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the title of the badge should have a gradient applied to it:
    private let isTitleColorGradient: Bool
    
    /// Background color of the badge:
    private let backgroundColor: Color
    
    /// Starting color of the gradient of the background of the badge if applicable:
    private let backgroundGradientStart: Color
    
    /// Ending color of the gradient of the background of the badge if applicable:
    private let backgroundGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the background of the badge should have a gradient applied to it:
    private let isBackgroundColorGradient: Bool
    
    /// 'Bool' value indicating whether or not the border of the badge should be shown at all:
    private let isShowingBorder: Bool
    
    /// Color of the border of the badge:
    private let borderColor: Color
    
    /// Starting color of the gradient of the border of the badge if applicable:
    private let borderGradientStart: Color
    
    /// Ending color of the gradient of the border of the badge if applicable:
    private let borderGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the border of the badge should have a gradient applied to it:
    private let isBorderColorGradient: Bool
    
    /// Size of the badge:
    private let size: NT_BadgeSize
    
    init(
        isShowingIcon: Bool = false,
        icon: String = Icons.mailStack,
        iconSymbolVariant: SymbolVariants = .fill,
        iconColor: Color = .white,
        iconGradientStart: Color = .blueGradientStart,
        iconGradientEnd: Color = .blueGradientEnd,
        isIconColorGradient: Bool = false,
        title: String,
        isTitleLocalized: Bool = true,
        titleTextCase: Text.Case? = .uppercase,
        titleAlignment: TextAlignment = .center,
        titleColor: Color = .white,
        titleGradientStart: Color = .blueGradientStart,
        titleGradientEnd: Color = .blueGradientEnd,
        isTitleColorGradient: Bool = false,
        backgroundColor: Color = .accent,
        backgroundGradientStart: Color = .blueGradientStart,
        backgroundGradientEnd: Color = .blueGradientEnd,
        isBackgroundColorGradient: Bool = true,
        isShowingBorder: Bool = true,
        borderColor: Color = .init(.systemBackground),
        borderGradientStart: Color = .blueGradientStart,
        borderGradientEnd: Color = .blueGradientEnd,
        isBorderColorGradient: Bool = false,
        size: NT_BadgeSize = .large
    ) {
        
        /// Properties initialization:
        self.isShowingIcon = isShowingIcon
        self.iconSymbolVariant = iconSymbolVariant
        self.icon = icon
        self.iconColor = iconColor
        self.iconGradientStart = iconGradientStart
        self.iconGradientEnd = iconGradientEnd
        self.isIconColorGradient = isIconColorGradient
        self.title = title
        self.isTitleLocalized = isTitleLocalized
        self.titleTextCase = titleTextCase
        self.titleAlignment = titleAlignment
        self.titleColor = titleColor
        self.titleGradientStart = titleGradientStart
        self.titleGradientEnd = titleGradientEnd
        self.isTitleColorGradient = isTitleColorGradient
        self.backgroundColor = backgroundColor
        self.backgroundGradientStart = backgroundGradientStart
        self.backgroundGradientEnd = backgroundGradientEnd
        self.isBackgroundColorGradient = isBackgroundColorGradient
        self.isShowingBorder = isShowingBorder
        self.borderColor = borderColor
        self.borderGradientStart = borderGradientStart
        self.borderGradientEnd = borderGradientEnd
        self.isBorderColorGradient = isBorderColorGradient
        self.size = size
    }
    
    // MARK: - Private computed properties:
    
    /// Font of the icon of the badge that is based on its size:
    private var iconFont: Font {
        size.iconFont
    }
    
    /// Size of the frame of the icon of the badge that is based on its size:
    private var iconFrame: CGFloat? {
        size.iconFrame
    }
    
    /// Font of the title of the badge that is based on its size:
    private var titleFont: Font {
        size.titleFont
    }
    
    /// Spacing between the content of the badge that is based on its size:
    private var spacing: Double {
        size.spacing
    }
    
    /// Vertical padding of the badge that is based on its size:
    private var verticalPadding: Double {
        size.verticalPadding
    }
    
    /// Horizontal padding of the badge that is based on its size:
    private var horizontalPadding: Double {
        size.horizontalPadding
    }
    
    /// Radius of the rounded corners of the badge that is based on its size:
    private var cornerRadius: Double {
        size.cornerRadius
    }
    
    /// Style of the rounded corners of the badge that is based on its size:
    private var cornerStyle: RoundedCornerStyle {
        size.cornerStyle
    }
    
    /// Width of the border of the badge that is based on its size:
    private var borderWidth: Double {
        isShowingBorder ? size.borderWidth : 0
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .padding(
                .vertical,
                verticalPadding
            )
            .padding(
                .horizontal,
                horizontalPadding
            )
            .gradientBackground(
                color: backgroundColor,
                gradientStart: backgroundGradientStart,
                gradientEnd: backgroundGradientEnd,
                isGradient: isBackgroundColorGradient
            )
            .roundedCorners(
                cornerRadius: cornerRadius,
                cornerStyle: cornerStyle
            )
            .overlay(border)
    }
}

// MARK: - Border:

private extension BadgeView {
    private var border: some View {
        RoundedRectangle(
            cornerRadius: cornerRadius,
            style: cornerStyle
        )
        .gradientBorder(
            width: borderWidth,
            color: borderColor,
            gradientStart: borderGradientStart,
            gradientEnd: borderGradientEnd,
            isGradient: isBorderColorGradient
        )
    }
}

// MARK: - Item:

private extension BadgeView {
    private var item: some View {
        HStack(
            alignment: .center,
            spacing: spacing
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        iconContent
        titleContent
    }
}

// MARK: - Icon:

private extension BadgeView {
    @ViewBuilder
    private var iconContent: some View {
        if isShowingIcon {
            iconItem
        }
    }
    
    private var iconItem: some View {
        Image(systemName: icon)
            .symbolVariant(iconSymbolVariant)
            .font(iconFont)
            .foregroundGradient(
                color: iconColor,
                gradientStart: iconGradientStart,
                gradientEnd: iconGradientEnd,
                isGradient: isIconColorGradient
            )
            .frame(
                width: iconFrame,
                height: iconFrame,
                alignment: .center
            )
    }
}

// MARK: - Title:

private extension BadgeView {
    private var titleContent: some View {
        titleItem
            .font(titleFont)
            .textCase(titleTextCase)
            .multilineTextAlignment(titleAlignment)
            .foregroundStyle(titleColor)
            .foregroundGradient(
                color: titleColor,
                gradientStart: titleGradientStart,
                gradientEnd: titleGradientEnd,
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
}

// MARK: - Preview:

#Preview {
    BadgeView(
        isShowingIcon: false,
        icon: Icons.mailStack,
        iconSymbolVariant: .fill,
        iconColor: .white,
        iconGradientStart: .blueGradientStart,
        iconGradientEnd: .blueGradientEnd,
        isIconColorGradient: false,
        title: "Title",
        isTitleLocalized: true,
        titleTextCase: .uppercase,
        titleAlignment: .center,
        titleColor: .white,
        titleGradientStart: .blueGradientStart,
        titleGradientEnd: .blueGradientEnd,
        isTitleColorGradient: false,
        backgroundColor: .accent,
        backgroundGradientStart: .blueGradientStart,
        backgroundGradientEnd: .blueGradientEnd,
        isBackgroundColorGradient: true,
        isShowingBorder: true,
        borderColor: .init(.systemBackground),
        borderGradientStart: .blueGradientStart,
        borderGradientEnd: .blueGradientEnd,
        isBorderColorGradient: false,
        size: .large
    )
    .padding()
}
