//
//  UnevenRoundedCornersModifier.swift
//  Native
//

import SwiftUI

struct UnevenRoundedCornersModifier: ViewModifier {
    
    // MARK: - Private properties:
    
    /// Radius of the top leading rounded corner:
    private let topLeadingCornerRadius: Double
    
    /// Radius of the bottom leading rounded corner:
    private let bottomLeadingCornerRadius: Double
    
    /// Radius of the top bottom trailing corner:
    private let bottomTrailingCornerRadius: Double
    
    /// Radius of the top trailing rounded corner:
    private let topTrailingCornerRadius: Double
    
    /// Style of the rounded corners:
    private let cornerStyle: RoundedCornerStyle
    
    init(
        topLeadingCornerRadius: Double,
        bottomLeadingCornerRadius: Double,
        bottomTrailingCornerRadius: Double,
        topTrailingCornerRadius: Double,
        cornerStyle: RoundedCornerStyle
    ) {
        
        /// Properties initialization:
        self.topLeadingCornerRadius = topLeadingCornerRadius
        self.bottomLeadingCornerRadius = bottomLeadingCornerRadius
        self.bottomTrailingCornerRadius = bottomTrailingCornerRadius
        self.topTrailingCornerRadius = topTrailingCornerRadius
        self.cornerStyle = cornerStyle
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the corners should actually be rounded:
    private var isRoundedCorners: Bool {
        topLeadingCornerRadius > 0
        || bottomLeadingCornerRadius > 0
        || bottomTrailingCornerRadius > 0
        || topTrailingCornerRadius > 0
    }
    
    // MARK: - View:
    
    func body(content: Content) -> some View {
        if isRoundedCorners {
            roundedCorners(content)
        } else {
            content
        }
    }
    
    private func roundedCorners(_ content: Content) -> some View {
        content
            .clipShape(
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: topLeadingCornerRadius,
                        bottomLeading: bottomLeadingCornerRadius,
                        bottomTrailing: bottomTrailingCornerRadius,
                        topTrailing: topTrailingCornerRadius
                    ),
                    style: cornerStyle
                )
            )
    }
}

// MARK: - Modifier:

extension View {
    
    // MARK: - Functions:
    
    /// Returns the modifier that adds the uneven rounded corners to the view:
    func unevenRoundedCorners(
        topLeadingCornerRadius: Double = 0,
        bottomLeadingCornerRadius: Double = 0,
        bottomTrailingCornerRadius: Double = 0,
        topTrailingCornerRadius: Double = 0,
        cornerStyle: RoundedCornerStyle = .continuous
    ) -> some View {
        modifier(
            UnevenRoundedCornersModifier(
                topLeadingCornerRadius: topLeadingCornerRadius,
                bottomLeadingCornerRadius: bottomLeadingCornerRadius,
                bottomTrailingCornerRadius: bottomTrailingCornerRadius,
                topTrailingCornerRadius: topTrailingCornerRadius,
                cornerStyle: cornerStyle
            )
        )
    }
}

// MARK: - Preview:

#Preview {
    Text("Preview")
        .font(.largeTitle.bold())
        .foregroundStyle(.white)
        .frame(
            width: 200,
            height: 200,
            alignment: .center
        )
        .background(
            LinearGradient(
                colors: [
                    .blueGradientStart,
                    .blueGradientEnd
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .unevenRoundedCorners(
            topLeadingCornerRadius: 48,
            bottomLeadingCornerRadius: 48,
            bottomTrailingCornerRadius: 0,
            topTrailingCornerRadius: 48,
            cornerStyle: .continuous
        )
        .padding()
}
