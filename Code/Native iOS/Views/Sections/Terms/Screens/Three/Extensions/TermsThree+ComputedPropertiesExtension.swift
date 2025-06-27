//
//  TermsThree+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension TermsThreeView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not an array of the overview items for the terms, as well as an array of the sections with the terms to display are both empty:
    var isEmpty: Bool {
        overviewItems.isEmpty && sections.isEmpty
    }
    
    /// Color of the background of the view:
    var backgroundColor: Color {
        .init(.systemGroupedBackground)
    }
    
    /// Opacity of the loading indicator:
    var loadingOpacity: Double {
        isFetching ? 1 : 0
    }
    
    /// Opacity of the 'No Terms' overlay:
    var noTermsOpacity: Double {
        isFetching || !isEmpty ? 0 : 1
    }
}
