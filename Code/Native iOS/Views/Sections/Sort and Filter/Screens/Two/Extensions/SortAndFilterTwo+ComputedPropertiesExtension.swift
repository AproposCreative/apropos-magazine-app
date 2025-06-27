//
//  SortAndFilterTwo+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension SortAndFilterTwoView {
    
    // MARK: - Computed properties:
    
    /// An array of the location filters to select from:
    var locationFilters: [NT_AccommodationLocationFilter] {
        NT_AccommodationLocationFilter.allCases
    }
    
    /// An array of the category filters to select from:
    var categoryFilters: [NT_AccommodationCategoryFilter] {
        NT_AccommodationCategoryFilter.allCases
    }
    
    /// An array of the level of service filters to select from:
    var levelOfServiceFilters: [NT_AccommodationLevelOfServiceFilter] {
        NT_AccommodationLevelOfServiceFilter.allCases
    }
    
    /// An array of the room type filters to select from:
    var roomTypeFilters: [NT_AccommodationRoomTypeFilter] {
        NT_AccommodationRoomTypeFilter.allCases
    }
    
    /// An array of the amenities filters to select from:
    var amenitiesFilters: [NT_AccommodationAmenitiesFilter] {
        NT_AccommodationAmenitiesFilter.allCases
    }
    
    /// An array of the Wi-Fi filters to select from:
    var wiFiFilters: [NT_AccommodationWiFiFilter] {
        NT_AccommodationWiFiFilter.allCases
    }
    
    /// An array of the airport shuttle service filters to select from:
    var airportShuttleServiceFilters: [NT_AccommodationAirportShuttleServiceFilter] {
        NT_AccommodationAirportShuttleServiceFilter.allCases
    }
    
    /// An array of the breakfast filters to select from:
    var breakfastFilters: [NT_AccommodationBreakfastFilter] {
        NT_AccommodationBreakfastFilter.allCases
    }
    
    /// An array of the cancellation policy filters to select from:
    var cancellationPolicyFilters: [NT_AccommodationCancellationPolicyFilter] {
        NT_AccommodationCancellationPolicyFilter.allCases
    }
    
    /// An array of the reviews filters to select from:
    var reviewsFilters: [NT_AccommodationReviewsFilter] {
        NT_AccommodationReviewsFilter.allCases
    }
    
    /// Count of the options of the given location filter as a string:
    var locationFilterOptionsCount: String {
        "\(locationFilters.count) options"
    }
    
    /// Count of the options of the given category filter as a string:
    var categoryFilterOptionsCount: String {
        "\(categoryFilters.count) options"
    }
    
    /// Count of the options of the given level of service filter as a string:
    var levelOfServiceFilterOptionsCount: String {
        "\(levelOfServiceFilters.count) options"
    }
    
    /// Count of the options of the given room type filter as a string:
    var roomTypeFilterOptionsCount: String {
        "\(roomTypeFilters.count) options"
    }
    
    /// Count of the options of the given amenities filter as a string:
    var amenitiesFilterOptionsCount: String {
        "\(amenitiesFilters.count) options"
    }
    
    /// Count of the options of the given Wi-Fi filter as a string:
    var wiFiFilterOptionsCount: String {
        "\(wiFiFilters.count) options"
    }
    
    /// Count of the options of the given airport shuttle service filter as a string:
    var airportShuttleServiceFilterOptionsCount: String {
        "\(airportShuttleServiceFilters.count) options"
    }
    
    /// Count of the options of the given breakfast filter as a string:
    var breakfastFilterOptionsCount: String {
        "\(breakfastFilters.count) options"
    }
    
    /// Count of the options of the given cancellation policy filter as a string:
    var cancellationPolicyFilterOptionsCount: String {
        "\(cancellationPolicyFilters.count) options"
    }
    
    /// Count of the options of the given reviews filter as a string:
    var reviewsFilterOptionsCount: String {
        "\(reviewsFilters.count) options"
    }
}
