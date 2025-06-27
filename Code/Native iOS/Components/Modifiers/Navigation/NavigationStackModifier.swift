//
//  NavigationStackModifier.swift
//  Native
//

import SwiftUI

struct NavigationStackModifier: ViewModifier {
    
    // MARK: - Private properties:
    
    /// 'Bool' value indicating whether or not the view should be embedded into the 'Navigation Stack':
    private let isEmbedding: Bool
    
    init(isEmbedding: Bool) {
        
        /// Properties initialization:
        self.isEmbedding = isEmbedding
    }
    
    // MARK: - View:
    
    func body(content: Content) -> some View {
        if isEmbedding {
            navigationStack(content)
        } else {
            content
        }
    }
    
    private func navigationStack(_ content: Content) -> some View {
        NavigationStack {
            content
        }
    }
}

// MARK: - Modifier:

extension View {
    
    // MARK: - Functions:
    
    /// Returns the modifier that embeds the view into the 'Navigation Stack' if needed:
    func navigationStack(isEmbedding: Bool = true) -> some View {
        modifier(NavigationStackModifier(isEmbedding: isEmbedding))
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
        .navigationStack(isEmbedding: true)
}
