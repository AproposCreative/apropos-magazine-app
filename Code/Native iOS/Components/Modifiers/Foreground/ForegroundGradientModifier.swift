//
//  ForegroundGradientModifier.swift
//  Native
//

import SwiftUI

struct ForegroundGradientModifier: ViewModifier {
    
    // MARK: - Private properties:
    
    /// Color of the foreground of the view if the gradient isn't needed in the certain use cases:
    private let color: Color?
    
    /// Starting color of the gradient of the foreground of the view:
    private let gradientStart: Color
    
    /// Ending color of the gradient of the foreground of the view:
    private let gradientEnd: Color
    
    /// 'Bool' value indicating whether or not the foreground color of the view should have a gradient applied to it:
    private let isGradient: Bool
    
    /// 'Bool' value indicating whether or not the icon is displayed in the sidebar which is needed to handle its tint color correctly:
    private let isSidebar: Bool
    
    init(
        color: Color?,
        gradientStart: Color,
        gradientEnd: Color,
        isGradient: Bool,
        isSidebar: Bool
    ) {
        
        /// Properties initialization:
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.isGradient = isGradient
        self.isSidebar = isSidebar
    }
    
    // MARK: - Private computed properties:
    
    /// An actual gradient of the foreground of the view that is based on the starting and the ending colors:
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
        if isSidebar {
            sidebarColor(content)
        } else {
            colorContent(content)
        }
    }
}

// MARK: - Sidebar color:

private extension ForegroundGradientModifier {
    @ViewBuilder
    private func sidebarColor(_ content: Content) -> some View {
        if isGradient {
            sidebarColorGradientContent(content)
        } else {
            sidebarColorContent(content)
        }
    }
    
    private func sidebarColorGradientContent(_ content: Content) -> some View {
        content
            .tint(gradient)
    }
    
    private func sidebarColorContent(_ content: Content) -> some View {
        content
            .tint(color)
    }
}

// MARK: - Color:

private extension ForegroundGradientModifier {
    @ViewBuilder
    private func colorContent(_ content: Content) -> some View {
        if isGradient {
            colorGradientContent(content)
        } else {
            colorItem(content)
        }
    }
    
    private func colorGradientContent(_ content: Content) -> some View {
        content
            .foregroundStyle(gradient)
    }
    
    private func colorItem(_ content: Content) -> some View {
        content
            .optionalForegroundStyle(color)
    }
}

// MARK: - Modifier:

extension View {
    
    // MARK: - Functions:
    
    /// Returns the modifier that adds a gradient to the view's foreground:
    func foregroundGradient(
        color: Color? = .blue,
        gradientStart: Color,
        gradientEnd: Color,
        isGradient: Bool = true,
        isSidebar: Bool = false
    ) -> some View {
        modifier(
            ForegroundGradientModifier(
                color: color,
                gradientStart: gradientStart,
                gradientEnd: gradientEnd,
                isGradient: isGradient,
                isSidebar: isSidebar
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
        .foregroundGradient(
            color: .blue,
            gradientStart: .blueGradientStart,
            gradientEnd: .blueGradientEnd,
            isGradient: true,
            isSidebar: false
        )
        .frame(
            width: 144,
            height: 144,
            alignment: .center
        )
        .padding()
}
