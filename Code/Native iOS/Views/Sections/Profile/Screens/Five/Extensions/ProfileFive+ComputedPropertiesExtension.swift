//
//  ProfileFive+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension ProfileFiveView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not there is an author to display the details for:
    var isNoAuthor: Bool {
        author == nil
    }
}
