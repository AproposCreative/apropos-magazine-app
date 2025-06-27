//
//  View+Extension.swift
//  Native
//

import SwiftUI

extension View {
    
    // MARK: - Functions:
    
    /// Returns the clipped view if needed:
    @ViewBuilder
    func isClipped(_ isClipped: Bool) -> some View {
        if isClipped {
            self
                .clipped()
        } else {
            self
        }
    }
}
