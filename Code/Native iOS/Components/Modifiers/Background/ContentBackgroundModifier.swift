//
//  ContentBackgroundModifier.swift
//  Native
//

import SwiftUI

struct ContentBackgroundModifier: ViewModifier {
    
    // MARK: - Private properties:
    
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
    
    init(
        verticalPadding: Double,
        horizontalPadding: Double,
        maxHeight: CGFloat?,
        maxHeightAlignment: Alignment,
        isShowingBackground: Bool,
        backgroundColor: Color,
        backgroundGradientStart: Color,
        backgroundGradientEnd: Color,
        isBackgroundColorGradient: Bool,
        cornerRadius: Double,
        cornerStyle: RoundedCornerStyle,
        borderWidth: Double,
        borderColor: Color,
        borderGradientStart: Color,
        borderGradientEnd: Color,
        isBorderGradient: Bool
    ) {
        
        /// Properties initialization:
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
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the border of the view should be shown:
    private var isShowingBorder: Bool {
        borderWidth > 0
    }
    
    /// Content of the color of the background of the view:
    private var backgroundColorContent: Color {
        if isShowingBackground {
            return backgroundColor
        } else {
            return .clear
        }
    }
    
    /// Content of the starting color of the gradient of the background of the view:
    private var backgroundGradientStartContent: Color {
        if isShowingBackground {
            return backgroundGradientStart
        } else {
            return .clear
        }
    }
    
    /// Content of the ending color of the gradient of the background of the view:
    private var backgroundGradientEndContent: Color {
        if isShowingBackground {
            return backgroundGradientEnd
        } else {
            return .clear
        }
    }
    
    /// Gradient of the border of the view if applicable:
    private var borderGradient: LinearGradient {
        .init(
            colors: [
                borderGradientStart,
                borderGradientEnd
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    // MARK: - View:
    
    func body(content: Content) -> some View {
        self.content(content)
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
            .overlay(border)
    }
    
    private func content(_ content: Content) -> some View {
        content
            .padding(
                .vertical,
                verticalPadding
            )
            .padding(
                .horizontal,
                horizontalPadding
            )
            .frame(
                maxHeight: maxHeight,
                alignment: maxHeightAlignment
            )
    }
}

// MARK: - Border:

private extension ContentBackgroundModifier {
    @ViewBuilder
    private var border: some View {
        if isShowingBorder {
            borderContent
        }
    }
    
    @ViewBuilder
    private var borderContent: some View {
        if isBorderGradient {
            gradientBorderItem
        } else {
            borderItem
        }
    }
    
    private var gradientBorderItem: some View {
        RoundedRectangle(
            cornerRadius: cornerRadius,
            style: cornerStyle
        )
        .stroke(
            borderGradient,
            lineWidth: borderWidth
        )
    }
    
    private var borderItem: some View {
        RoundedRectangle(
            cornerRadius: cornerRadius,
            style: cornerStyle
        )
        .stroke(
            borderColor,
            lineWidth: borderWidth
        )
    }
}

// MARK: - Modifier:

extension View {
    
    // MARK: - Functions:
    
    /// Returns the modifier that adds the background to the view if needed:
    func contentBackground(
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
        isBorderGradient: Bool = true
    ) -> some View {
        modifier(
            ContentBackgroundModifier(
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
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        TitleSubtitleView(
            title: "Title",
            subtitle: "Subtitle",
            maxWidth: .infinity,
            maxWidthAlignment: .leading
        )
        .contentBackground(
            verticalPadding: 12,
            horizontalPadding: 12,
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
        )
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
