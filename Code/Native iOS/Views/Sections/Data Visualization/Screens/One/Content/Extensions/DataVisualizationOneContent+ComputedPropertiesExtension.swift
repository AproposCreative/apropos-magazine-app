//
//  DataVisualizationOneContent+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension DataVisualizationOneContentView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not an array of the overview items to display, as well as various arrays with the data to display in the charts are all empty:
    var isEmpty: Bool {
        overviewItems.isEmpty
        && activeUsersData.isEmpty
        && newDownloadsData.isEmpty
        && reviewsData.isEmpty
        && totalUsersData.isEmpty
    }
}
