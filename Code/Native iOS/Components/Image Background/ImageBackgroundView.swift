//
//  ImageBackgroundView.swift
//  Native
//

import SwiftUI

struct ImageBackgroundView: View {
    
    // MARK: - Private properties:
    
    /// An actual image to display:
    private let image: Image
    
    /// 'Bool' value indicating whether or not the image should be resizable or if it should just keep its original size:
    private let isResizable: Bool
    
    /// 'Bool' value indicating whether or not the image should be clipped based on its frame:
    private let isClipped: Bool
    
    /// Width of the image if applicable:
    private let width: CGFloat?
    
    /// Height of the image if applicable:
    private let height: CGFloat?
    
    /// Maximum width that the image should have if applicable:
    private let maxWidth: CGFloat?
    
    /// Alignment of the image:
    private let alignment: Alignment
    
    /// 'Bool' value indicating whether or not the image should take the full width:
    private let isFullWidth: Bool
    
    /// 'Bool' value indicating whether or not the background of the image should be shown at all:
    private let isShowingBackground: Bool
    
    /// Color of the background of the image:
    private let backgroundColor: Color
    
    /// Starting color of the gradient of the background of the image if applicable:
    private let backgroundGradientStart: Color
    
    /// Ending color of the gradient of the background of the image if applicable:
    private let backgroundGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the background color of the image should have a gradient applied to it:
    private let isBackgroundColorGradient: Bool
    
    /// Radius of the rounded corners of the image:
    private let cornerRadius: Double
    
    /// Style of the rounded corners of the image:
    private let cornerStyle: RoundedCornerStyle
    
    /// Width of the border of the image:
    private let borderWidth: Double
    
    /// Color of the border of the image:
    private let borderColor: Color
    
    /// Accessibility label of the image:
    private let accessibilityLabel: String
    
    /// 'Bool' value indicating whether or not the accessibility label of the image should be localized:
    private let isAccessibilityLabelLocalized: Bool
    
    /// Action of the image after single tapping on it if applicable:
    private let singleTapAction: (() -> ())?
    
    /// Action of the image after double tapping on it if applicable:
    private let doubleTapAction: (() -> ())?
    
    init(
        image: Image,
        isResizable: Bool = true,
        isClipped: Bool = true,
        width: CGFloat? = 304,
        height: CGFloat? = 304,
        maxWidth: CGFloat? = nil,
        alignment: Alignment = .center,
        isFullWidth: Bool = true,
        isShowingBackground: Bool = true,
        backgroundColor: Color = .accent,
        backgroundGradientStart: Color = .blueGradientStart,
        backgroundGradientEnd: Color = .blueGradientEnd,
        isBackgroundColorGradient: Bool = true,
        cornerRadius: Double = 24,
        cornerStyle: RoundedCornerStyle = .continuous,
        borderWidth: Double = 0,
        borderColor: Color = .init(.secondarySystemGroupedBackground),
        accessibilityLabel: String = "",
        isAccessibilityLabelLocalized: Bool = true,
        singleTapAction: (() -> ())? = nil,
        doubleTapAction: (() -> ())? = nil
    ) {
        
        /// Properties initialization:
        self.image = image
        self.isResizable = isResizable
        self.isClipped = isClipped
        self.width = width
        self.height = height
        self.maxWidth = maxWidth
        self.alignment = alignment
        self.isFullWidth = isFullWidth
        self.isShowingBackground = isShowingBackground
        self.backgroundColor = backgroundColor
        self.backgroundGradientStart = backgroundGradientStart
        self.backgroundGradientEnd = backgroundGradientEnd
        self.isBackgroundColorGradient = isBackgroundColorGradient
        self.cornerRadius = cornerRadius
        self.cornerStyle = cornerStyle
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.accessibilityLabel = accessibilityLabel
        self.isAccessibilityLabelLocalized = isAccessibilityLabelLocalized
        self.singleTapAction = singleTapAction
        self.doubleTapAction = doubleTapAction
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the border of the image should be shown at all:
    private var isShowingBorder: Bool {
        borderWidth > 0
    }
    
    /// 'Bool' value indicating whether or not the image has actions applied to it:
    private var doesHaveActions: Bool {
        singleTapAction != nil
        || doubleTapAction != nil
    }
    
    /// Content of the color of the background of the image:
    private var backgroundColorContent: Color {
        if isShowingBackground {
            return backgroundColor
        } else {
            return .clear
        }
    }
    
    /// Content of the starting color of the gradient of the background of the image:
    private var backgroundGradientStartContent: Color {
        if isShowingBackground {
            return backgroundGradientStart
        } else {
            return .clear
        }
    }
    
    /// Content of the ending color of the gradient of the background of the image:
    private var backgroundGradientEndContent: Color {
        if isShowingBackground {
            return backgroundGradientEnd
        } else {
            return .clear
        }
    }
    
    /// Content of the width of the image based on whether or not it should take the full width:
    private var widthContent: CGFloat? {
        isFullWidth ? nil : width
    }
    
    /// Content of the maximum width of the image based on whether or not it should take the full width if applicable:
    private var maxWidthContent: CGFloat? {
        isFullWidth ? .infinity : maxWidth
    }
    
    /// Value of the accessibility label of the image if applicable:
    private var indicatorAccessibilityLabelValue: Text {
        isAccessibilityLabelLocalized
        ? .init(.init(accessibilityLabel))
        : .init(accessibilityLabel)
    }
    
    /// Accessibility traits of the image if it has actions applied to it to indicate that it's an actual button:
    private var accessibilityTraits: AccessibilityTraits {
        doesHaveActions ? .isButton : []
    }
    
    /// Accessibility child behavior of the image that is based on whether or not it has actions applied to it:
    private var accessibilityChildBehavior: AccessibilityChildBehavior {
        doesHaveActions ? .combine : .ignore
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        image
            .isResizable(isResizable)
            .frame(
                width: widthContent,
                height: height,
                alignment: alignment
            )
            .frame(
                minWidth: width,
                maxWidth: maxWidthContent,
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
            .isClipped(isClipped)
            .contentShape(
                .rect(
                    cornerRadius: cornerRadius,
                    style: cornerStyle
                )
            )
            .overlay(border)
            .optionalTapGesture(
                count: 2,
                action: doubleTapAction
            )
            .optionalTapGesture(
                count: 1,
                action: singleTapAction
            )
            .accessibilityAddTraits(accessibilityTraits)
            .accessibilityElement(children: accessibilityChildBehavior)
            .accessibilityLabel(indicatorAccessibilityLabelValue)
    }
}

// MARK: - Border:

private extension ImageBackgroundView {
    @ViewBuilder
    private var border: some View {
        if isShowingBorder {
            borderContent
        }
    }
    
    private var borderContent: some View {
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

// MARK: - Preview:

#Preview {
    ImageBackgroundView(
        image: .init(.onboarding22),
        isResizable: true,
        isClipped: true,
        width: 304,
        height: 304,
        maxWidth: nil,
        alignment: .center,
        isFullWidth: true,
        isShowingBackground: true,
        backgroundColor: .accent,
        backgroundGradientStart: .blueGradientStart,
        backgroundGradientEnd: .blueGradientEnd,
        isBackgroundColorGradient: true,
        cornerRadius: 24,
        cornerStyle: .continuous,
        borderWidth: 0,
        borderColor: .init(.secondarySystemGroupedBackground),
        accessibilityLabel: "",
        isAccessibilityLabelLocalized: true
    ) {
        
    } doubleTapAction: {
        
    }
    .padding()
}
