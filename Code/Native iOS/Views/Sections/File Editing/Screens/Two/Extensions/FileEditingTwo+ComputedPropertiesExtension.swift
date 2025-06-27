//
//  FileEditingTwo+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension FileEditingTwoView {
    
    // MARK: - Computed properties:
    
    /// Opacity of the loading indicator:
    var loadingOpacity: Double {
        isFetching ? 1 : 0
    }
    
    /// Opacity of the 'No Categories' overlay:
    var noCategoriesOpacity: Double {
        (
            isFetching
            || !categories.isEmpty
        ) ? 0 : 1
    }
}
