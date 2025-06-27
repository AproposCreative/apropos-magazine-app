//
//  PaywallThirteenSocialProof+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension PaywallThirteenSocialProofView {
    
    // MARK: - Computed properties:
    
    /// An array of the social proof items to display:
    var socialProofItems: [NT_SocialProof] {
        NT_SocialProof.allCases
    }
    
    /// An array of the columns to display the social proof items in the grid:
    var columns: [GridItem] {
        [
            .init(
                .adaptive(
                    minimum: gridItemMinWidth,
                    maximum: gridItemMaxWidth
                ),
                spacing: 12,
                alignment: .center
            )
        ]
    }
    
    /// Font of the title of the view:
    var titleFont: Font {
        .system(
            .footnote,
            design: .default,
            weight: .heavy
        )
    }
    
    /// Font of the icon of the view:
    var iconFont: Font {
        .system(
            size: 28,
            weight: .semibold,
            design: .default
        )
    }
    
    /// Color of the view:
    var color: Color {
        .white
    }
    
    /// Size of the frame of the icon of the view:
    var iconFrame: Double {
        32
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    private var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
    
    /// Minimum width that each of the grid items should have that is based on the size of the dynamic type that is currently selected:
    private var gridItemMinWidth: Double {
        shouldMoveContent ? 200 : 128
    }
    
    /// Maximum width that each of the grid items can have that is based on the size of the dynamic type that is currently selected:
    private var gridItemMaxWidth: Double {
        shouldMoveContent ? 400 : 200
    }
}
