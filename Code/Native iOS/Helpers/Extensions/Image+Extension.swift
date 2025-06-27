//
//  Image+Extension.swift
//  Native
//

import SwiftUI

extension Image {
    
    // MARK: - Functions:
    
    /// Returns the resizable image view if needed:
    @ViewBuilder
    func isResizable(_ isResizable: Bool) -> some View {
        if isResizable {
            self
                .resizable()
                .scaledToFill()
        } else {
            self
        }
    }
}
