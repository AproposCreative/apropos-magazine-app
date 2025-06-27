//
//  DarkColorSchemeModifier.swift
//  Native
//

import SwiftUI

struct DarkColorSchemeModifier: ViewModifier {
    
    // MARK: - Private properties:
    
    /// 'Bool' value indicating whether or not the view should have a dark color scheme applied to it:
    private let isDark: Bool
    
    init(isDark: Bool) {
        
        /// Properties initialization:
        self.isDark = isDark
    }
    
    // MARK: - View:
    
    func body(content: Content) -> some View {
        if isDark {
            darkContent(content)
        } else {
            content
        }
    }
    
    private func darkContent(_ content: Content) -> some View {
        content
            .environment(
                \.colorScheme,
                 .dark
            )
    }
}

// MARK: - Modifier:

extension View {
    
    // MARK: - Functions:
    
    /// Returns the modifier that applies the dark color scheme to the view if needed:
    func darkColorScheme(isDark: Bool = true) -> some View {
        modifier(DarkColorSchemeModifier(isDark: isDark))
    }
}

// MARK: - Preview:

#Preview {
    Text("Preview")
        .font(.body)
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .padding()
        .navigationTitle("Preview")
        .navigationStack()
        .darkColorScheme(isDark: true)
}
