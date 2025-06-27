//
//  DynamicTextHeightModifier.swift
//  Native
//

import SwiftUI

struct DynamicTextHeightModifier: ViewModifier {
    
    // MARK: - View:
    
    func body(content: Content) -> some View {
        content
            .fixedSize(
                horizontal: false,
                vertical: true
            )
    }
}

// MARK: - Modifier:

extension View {
    
    // MARK: - Functions:
    
    /// Returns the modifier:
    func dynamicTextHeight() -> some View {
        modifier(DynamicTextHeightModifier())
    }
}

// MARK: - Preview:

#Preview {
    Text("This is a very long preview text that is used to showcase this modifier in use. Please just note that this modifier isn't always required and in most cases there isn't a text cropping issue at all.")
        .dynamicTextHeight()
        .padding()
}
