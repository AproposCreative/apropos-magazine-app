//
//  LinearGradient+Extension.swift
//  Native
//

import SwiftUI

extension LinearGradient {
    
    // MARK: - Computed properties:
    
    /// Blue gradient:
    static var blue: Self {
        .init(
            colors: [
                .blueGradientStart,
                .blueGradientEnd
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
