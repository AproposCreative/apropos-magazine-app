//
//  OptionalTapGestureModifier.swift
//  Native
//

import SwiftUI

struct OptionalTapGestureModifier: ViewModifier {
    
    // MARK: - Private properties:
    
    /// Count of the taps that is needed for the tap gesture to trigger:
    private let count: Int
    
    /// An actual action of the tap gesture if applicable:
    private let action: (() -> ())?
    
    init(
        count: Int,
        action: (() -> ())?
    ) {
        
        /// Properties initialization:
        self.count = count
        self.action = action
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not an actual gesture should be enabled:
    private var isEnabled: Bool {
        action != nil
    }
    
    // MARK: - View:
    
    func body(content: Content) -> some View {
        if isEnabled {
            tapGesture(content)
        } else {
            content
        }
    }
    
    private func tapGesture(_ content: Content) -> some View {
        content
            .onTapGesture(count: count) {
                action?()
            }
    }
}

// MARK: - Modifier:

extension View {
    
    // MARK: - Functions:
    
    /// Returns the modifier that adds the tap gesture to the view optionally:
    func optionalTapGesture(
        count: Int = 1,
        action: (() -> ())?
    ) -> some View {
        modifier(
            OptionalTapGestureModifier(
                count: count,
                action: action
            )
        )
    }
}

// MARK: - Preview:

#Preview {
    Text("Preview")
        .padding()
        .optionalTapGesture(count: 1) {
            
        }
}
