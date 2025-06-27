//
//  MainSixContent+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension MainSixContentView {
    
    // MARK: - Computed properties:
    
    /// Image to display as the avatar:
    var avatarImage: Image {
        .init(.main61)
    }
    
    /// Opacity of the loading indicator:
    var loadingOpacity: Double {
        isFetching ? 1 : 0
    }
    
    /// Opacity of the 'Nothing Here' overlay:
    var nothingHereOpacity: Double {
        isFetching || (
            !stories.isEmpty
            || !posts.isEmpty
            || !accounts.isEmpty
        ) ? 0 : 1
    }
}
