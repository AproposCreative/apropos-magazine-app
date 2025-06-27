//
//  SortAndFilterTwo+FunctionsExtension.swift
//  Native
//

import Foundation

extension SortAndFilterTwoView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given location filter:
    func title(_ filter: NT_AccommodationLocationFilter) -> String {
        filter.title
    }
    
    /// Returns the title of the given category filter:
    func title(_ filter: NT_AccommodationCategoryFilter) -> String {
        filter.title
    }
    
    /// Returns the title of the given level of service filter:
    func title(_ filter: NT_AccommodationLevelOfServiceFilter) -> String {
        filter.title
    }
    
    /// Returns the title of the given room type filter:
    func title(_ filter: NT_AccommodationRoomTypeFilter) -> String {
        filter.title
    }
    
    /// Returns the title of the given amenities filter:
    func title(_ filter: NT_AccommodationAmenitiesFilter) -> String {
        filter.title
    }
    
    /// Returns the title of the given Wi-Fi filter:
    func title(_ filter: NT_AccommodationWiFiFilter) -> String {
        filter.title
    }
    
    /// Returns the title of the given airport shuttle service filter:
    func title(_ filter: NT_AccommodationAirportShuttleServiceFilter) -> String {
        filter.title
    }
    
    /// Returns the title of the given breakfast filter:
    func title(_ filter: NT_AccommodationBreakfastFilter) -> String {
        filter.title
    }
    
    /// Returns the title of the given cancellation policy filter:
    func title(_ filter: NT_AccommodationCancellationPolicyFilter) -> String {
        filter.title
    }
    
    /// Returns the title of the given reviews filter:
    func title(_ filter: NT_AccommodationReviewsFilter) -> String {
        filter.title
    }
    
    /// Clears all of the filters that are currently selected:
    func clearAll() {
        
        /*
         
         NOTE: You can add your own logic for clearing all of the filters here.
         
         */
        
    }
    
    /// Applies all of the filters that are currently selected:
    func apply() {
        
        /*
         
         NOTE: You can add your own logic for applying all of the filters here.
         
         */
        
    }
    
    /// Triggers the haptic feedback:
    func triggerHapticFeedback() {
        
        /// Triggering the selection changed haptic feedback indicating that there was a change:
        HapticFeedbacks.selectionChanged()
    }
}
