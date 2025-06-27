//
//  SelectionView.swift
//  Native
//

import SwiftUI

struct SelectionView: View {
    
    // MARK: - Private properties:
    
    /// Color of the view:
    private let color: Color
    
    /// Starting color of the gradient of the view if applicable:
    private let gradientStart: Color
    
    /// Ending color of the gradient of the view if applicable:
    private let gradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the view should have a gradient applied to it:
    private let isColorGradient: Bool
    
    /// Width of the view:
    private let width: Double
    
    /// Height of the view:
    private let height: Double
    
    /// Width of the border of the view:
    private let borderWidth: Double
    
    /// Color of the corner of the view:
    private let cornerColor: Color
    
    /// Starting color of the gradient of the corner of the view if applicable:
    private let cornerGradientStart: Color
    
    /// Ending color of the gradient of the corner of the view if applicable:
    private let cornerGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the corner of the view should have a gradient applied to it:
    private let isCornerColorGradient: Bool
    
    /// Frame of the corner of the view:
    private let cornerFrame: Double
    
    /// Width of the border of the corner:
    private let cornerBorderWidth: Double
    
    /// Color of the border of the corner:
    private let cornerBorderColor: Color
    
    /// Starting color of the gradient of the border of the corner of the view if applicable:
    private let cornerBorderGradientStart: Color
    
    /// Ending color of the gradient of the border of the corner of the view if applicable:
    private let cornerBorderGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the border of the corner of the view should have a gradient applied to it:
    private let isCornerBorderColorGradient: Bool
    
    /// Current amount of the zoom into the content of the file that the layer is a part of which the selection is for:
    private let currentZoom: Double
    
    init(
        color: Color = .accent,
        gradientStart: Color = .blueGradientStart,
        gradientEnd: Color = .blueGradientEnd,
        isColorGradient: Bool = true,
        width: Double,
        height: Double,
        borderWidth: Double = 0.5,
        cornerColor: Color = .accent,
        cornerGradientStart: Color = .blueGradientStart,
        cornerGradientEnd: Color = .blueGradientEnd,
        isCornerColorGradient: Bool = true,
        cornerFrame: Double = 4,
        cornerBorderWidth: Double = 0.5,
        cornerBorderColor: Color = .white,
        cornerBorderGradientStart: Color = .blueGradientStart,
        cornerBorderGradientEnd: Color = .blueGradientEnd,
        isCornerBorderColorGradient: Bool = false,
        currentZoom: Double
    ) {
        
        /// Properties initialization:
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.isColorGradient = isColorGradient
        self.width = width
        self.height = height
        self.borderWidth = borderWidth
        self.cornerColor = cornerColor
        self.cornerGradientStart = cornerGradientStart
        self.cornerGradientEnd = cornerGradientEnd
        self.isCornerColorGradient = isCornerColorGradient
        self.cornerFrame = cornerFrame
        self.cornerBorderWidth = cornerBorderWidth
        self.cornerBorderColor = cornerBorderColor
        self.cornerBorderGradientStart = cornerBorderGradientStart
        self.cornerBorderGradientEnd = cornerBorderGradientEnd
        self.isCornerBorderColorGradient = isCornerBorderColorGradient
        self.currentZoom = currentZoom
    }
    
    // MARK: - Private computed properties:
    
    /// Content of the width of the border of the view that is based on the amount of the current zoom and its width:
    private var borderWidthContent: Double {
        borderWidth / currentZoom
    }
    
    /// Content of the frame of each of the corners that is based on the amount of the current zoom and its frame:
    private var cornerFrameContent: Double {
        cornerFrame / currentZoom
    }
    
    /// Content of the border of each of the corners that is based on the amount of the current zoom and its width:
    private var cornerBorderWidthContent: Double {
        cornerBorderWidth / currentZoom
    }
    
    /// Offset of each of the corners that is based on the size of the content of its frame:
    private var cornerOffset: Double {
        cornerFrameContent / 2
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        Rectangle()
            .gradientBorder(
                width: borderWidthContent,
                color: color,
                gradientStart: gradientStart,
                gradientEnd: gradientEnd,
                isGradient: isColorGradient
            )
            .frame(
                width: width,
                height: height,
                alignment: .center
            )
            .overlay(alignment: .topLeading) {
                topLeadingCorner
            }
            .overlay(alignment: .bottomLeading) {
                bottomLeadingCorner
            }
            .overlay(alignment: .topTrailing) {
                topTrailingCorner
            }
            .overlay(alignment: .bottomTrailing) {
                bottomTrailingCorner
            }
            .accessibilityAddTraits(.isSelected)
    }
}

// MARK: - Corner:

private extension SelectionView {
    private var topLeadingCorner: some View {
        cornerContent
            .offset(
                x: -cornerOffset,
                y: -cornerOffset
            )
    }
    
    private var bottomLeadingCorner: some View {
        cornerContent
            .offset(
                x: -cornerOffset,
                y: cornerOffset
            )
    }
    
    private var topTrailingCorner: some View {
        cornerContent
            .offset(
                x: cornerOffset,
                y: -cornerOffset
            )
    }
    
    private var bottomTrailingCorner: some View {
        cornerContent
            .offset(
                x: cornerOffset,
                y: cornerOffset
            )
    }
    
    private var cornerContent: some View {
        Circle()
            .gradientFill(
                color: cornerColor,
                gradientStart: cornerGradientStart,
                gradientEnd: cornerGradientEnd,
                isGradient: isCornerColorGradient
            )
            .frame(
                width: cornerFrameContent,
                height: cornerFrameContent,
                alignment: .center
            )
            .overlay(cornerBorder)
    }
    
    private var cornerBorder: some View {
        Circle()
            .gradientBorder(
                width: cornerBorderWidthContent,
                color: cornerBorderColor,
                gradientStart: cornerBorderGradientStart,
                gradientEnd: cornerBorderGradientEnd,
                isGradient: isCornerBorderColorGradient
            )
    }
}

// MARK: - Preview:

#Preview {
    SelectionView(
        color: .accent,
        gradientStart: .blueGradientStart,
        gradientEnd: .blueGradientEnd,
        isColorGradient: true,
        width: 100,
        height: 100,
        borderWidth: 0.5,
        cornerColor: .accent,
        cornerGradientStart: .blueGradientStart,
        cornerGradientEnd: .blueGradientEnd,
        isCornerColorGradient: true,
        cornerFrame: 4,
        cornerBorderWidth: 0.5,
        cornerBorderColor: .white,
        cornerBorderGradientStart: .blueGradientStart,
        cornerBorderGradientEnd: .blueGradientEnd,
        isCornerBorderColorGradient: false,
        currentZoom: 1
    )
    .padding()
}
