//
//  OptionalForegroundStyleModifier.swift
//  Native
//

import SwiftUI

struct OptionalForegroundStyleModifier: ViewModifier {
    
    // MARK: - Private properties:
    
    /// An actual color of the view if applicable:
    private let color: Color?
    
    init(color: Color?) {
        
        /// Properties initialization:
        self.color = color
    }
    
    // MARK: - View:
    
    func body(content: Content) -> some View {
        if let color {
            content
                .foregroundStyle(color)
        } else {
            content
        }
    }
}

// MARK: - Modifier:

extension View {
    
    // MARK: - Functions:
    
    /// Returns the modifier that adds the foreground style to the view optionally:
    func optionalForegroundStyle(_ color: Color?) -> some View {
        modifier(OptionalForegroundStyleModifier(color: color))
    }
}

// MARK: - Preview:

#Preview {
    Text("Preview")
        .optionalForegroundStyle(nil)
        .padding()
}
