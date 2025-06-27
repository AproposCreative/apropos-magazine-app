//
//  RoundedCornersModifier.swift
//  Native
//

import SwiftUI

struct RoundedCornersModifier: ViewModifier {
    
    // MARK: - Private properties:
    
    /// Radius of the rounded corners:
    private let cornerRadius: Double
    
    /// Style of the rounded corners:
    private let cornerStyle: RoundedCornerStyle
    
    init(
        cornerRadius: Double,
        cornerStyle: RoundedCornerStyle
    ) {
        
        /// Properties initialization:
        self.cornerRadius = cornerRadius
        self.cornerStyle = cornerStyle
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the corners should actually be rounded:
    private var isRoundedCorners: Bool {
        cornerRadius > 0
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
                .rect(
                    cornerRadius: cornerRadius,
                    style: cornerStyle
                )
            )
    }
}

// MARK: - Modifier:

extension View {
    
    // MARK: - Functions:
    
    /// Returns the modifier that adds the rounded corners to the view:
    func roundedCorners(
        cornerRadius: Double,
        cornerStyle: RoundedCornerStyle = .continuous
    ) -> some View {
        modifier(
            RoundedCornersModifier(
                cornerRadius: cornerRadius,
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
        .roundedCorners(
            cornerRadius: 48,
            cornerStyle: .continuous
        )
        .padding()
}
