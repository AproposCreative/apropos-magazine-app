//
//  GradientBackgroundModifier.swift
//  Native
//

import SwiftUI

struct GradientBackgroundModifier: ViewModifier {
    
    // MARK: - Private properties:
    
    /// Color of the background of the view if the gradient isn't needed in the certain use cases:
    private let color: Color
    
    /// Starting color of the gradient of the background of the view:
    private let gradientStart: Color
    
    /// Ending color of the gradient of the background of the view:
    private let gradientEnd: Color
    
    /// 'Bool' value indicating whether or not the background color of the view should have a gradient applied to it:
    private let isGradient: Bool
    
    init(
        color: Color,
        gradientStart: Color,
        gradientEnd: Color,
        isGradient: Bool
    ) {
        
        /// Properties initialization:
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.isGradient = isGradient
    }
    
    // MARK: - Private computed properties:
    
    /// An actual gradient of the background of the view that is based on the starting and the ending colors:
    private var gradient: LinearGradient {
        .init(
            colors: [
                gradientStart,
                gradientEnd
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    // MARK: - View:
    
    func body(content: Content) -> some View {
        if isGradient {
            colorGradientContent(content)
        } else {
            colorContent(content)
        }
    }
    
    private func colorGradientContent(_ content: Content) -> some View {
        content
            .background(gradient)
    }
    
    private func colorContent(_ content: Content) -> some View {
        content
            .background(color)
    }
}

// MARK: - Modifier:

extension View {
    
    // MARK: - Functions:
    
    /// Returns the modifier that adds a gradient to the view's background:
    func gradientBackground(
        color: Color,
        gradientStart: Color = .blueGradientStart,
        gradientEnd: Color = .blueGradientEnd,
        isGradient: Bool
    ) -> some View {
        modifier(
            GradientBackgroundModifier(
                color: color,
                gradientStart: gradientStart,
                gradientEnd: gradientEnd,
                isGradient: isGradient
            )
        )
    }
}

// MARK: - Preview:

#Preview {
    Image(systemName: Icons.mailStack)
        .symbolVariant(.fill)
        .font(
            .system(
                size: 96,
                weight: .semibold,
                design: .default
            )
        )
        .foregroundStyle(.white)
        .frame(
            width: 200,
            height: 200,
            alignment: .center
        )
        .gradientBackground(
            color: .blue,
            gradientStart: .blueGradientStart,
            gradientEnd: .blueGradientEnd,
            isGradient: true
        )
        .roundedCorners(
            cornerRadius: 48,
            cornerStyle: .continuous
        )
        .padding()
}
