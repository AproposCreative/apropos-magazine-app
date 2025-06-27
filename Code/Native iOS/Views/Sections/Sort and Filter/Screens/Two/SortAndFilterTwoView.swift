//
//  SortAndFilterTwoView.swift
//  Native
//

import SwiftUI

struct SortAndFilterTwoView: View {
    
    // MARK: - Private properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) private var dismiss
    
    /// Location filter that is currently selected:
    @State private var locationFilter: NT_AccommodationLocationFilter = .losAngeles
    
    /// Category filter that is currently selected:
    @State private var categoryFilter: NT_AccommodationCategoryFilter = .hotel
    
    /// Level of service filter that is currently selected:
    @State private var levelOfServiceFilter: NT_AccommodationLevelOfServiceFilter = .fiveStars
    
    /// Room type filter that is currently selected:
    @State private var roomTypeFilter: NT_AccommodationRoomTypeFilter = .suite
    
    /// Amenities filter that is currently selected:
    @State private var amenitiesFilter: NT_AccommodationAmenitiesFilter = .swimmingPool
    
    /// Wi-Fi filter that is currently selected:
    @State private var wiFiFilter: NT_AccommodationWiFiFilter = .yes
    
    /// Airport shuttle service filter that is currently selected:
    @State private var airportShuttleServiceFilter: NT_AccommodationAirportShuttleServiceFilter = .available
    
    /// Breakfast filter that is currently selected:
    @State private var breakfastFilter: NT_AccommodationBreakfastFilter = .included
    
    /// Cancellation policy filter that is currently selected:
    @State private var cancellationPolicyFilter: NT_AccommodationCancellationPolicyFilter = .free
    
    /// Reviews filter that is currently selected:
    @State private var reviewsFilter: NT_AccommodationReviewsFilter = .excellent
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .localizedNavigationTitle(title: "Filter")
            .toolbarButton(
                title: "Clear All",
                placement: .cancellationAction,
                action: clearAll
            )
            .toolbarButton(
                title: "Done",
                action: dismiss.callAsFunction
            )
            .onChange(of: locationFilter) { _, _ in
                triggerHapticFeedback()
            }
            .onChange(of: categoryFilter) { _, _ in
                triggerHapticFeedback()
            }
            .onChange(of: levelOfServiceFilter) { _, _ in
                triggerHapticFeedback()
            }
            .onChange(of: roomTypeFilter) { _, _ in
                triggerHapticFeedback()
            }
            .onChange(of: amenitiesFilter) { _, _ in
                triggerHapticFeedback()
            }
            .onChange(of: wiFiFilter) { _, _ in
                triggerHapticFeedback()
            }
            .onChange(of: airportShuttleServiceFilter) { _, _ in
                triggerHapticFeedback()
            }
            .onChange(of: breakfastFilter) { _, _ in
                triggerHapticFeedback()
            }
            .onChange(of: cancellationPolicyFilter) { _, _ in
                triggerHapticFeedback()
            }
            .onChange(of: reviewsFilter) { _, _ in
                triggerHapticFeedback()
            }
            .navigationStack()
    }
}

// MARK: - Item:

private extension SortAndFilterTwoView {
    private var item: some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        list
        toolbar
    }
}

// MARK: - List:

private extension SortAndFilterTwoView {
    private var list: some View {
        listContent
            .listStyle(.plain)
    }
    
    private var listContent: some View {
        List {
            listItem
        }
    }
    
    @ViewBuilder
    private var listItem: some View {
        locationFilterPicker
        categoryFilterPicker
        levelOfServiceFilterPicker
        roomTypeFilterPicker
        amenitiesFilterPicker
        wiFiFilterPicker
        airportShuttleServiceFilterPicker
        breakfastFilterPicker
        cancellationPolicyFilterPicker
        reviewsFilterPicker
    }
}

// MARK: - Location filter picker:

private extension SortAndFilterTwoView {
    private var locationFilterPicker: some View {
        locationFilterPickerContent
            .pickerStyle(.navigationLink)
    }
    
    private var locationFilterPickerContent: some View {
        Picker(selection: $locationFilter) {
            locationFiltersContent
        } label: {
            locationFilterPickerLabel
        }
    }
    
    private var locationFilterPickerLabel: some View {
        TitleSubtitleView(
            title: "Location",
            subtitle: locationFilterOptionsCount
        )
    }
    
    private var locationFiltersContent: some View {
        ForEach(
            locationFilters,
            content: locationFilter
        )
    }
    
    private func locationFilter(_ filter: NT_AccommodationLocationFilter) -> some View {
        Text(title(filter))
            .tag(filter)
    }
}

// MARK: - Category filter picker:

private extension SortAndFilterTwoView {
    private var categoryFilterPicker: some View {
        categoryFilterPickerContent
            .pickerStyle(.navigationLink)
    }
    
    private var categoryFilterPickerContent: some View {
        Picker(selection: $categoryFilter) {
            categoryFiltersContent
        } label: {
            categoryFilterPickerLabel
        }
    }
    
    private var categoryFilterPickerLabel: some View {
        TitleSubtitleView(
            title: "Category",
            subtitle: categoryFilterOptionsCount
        )
    }
    
    private var categoryFiltersContent: some View {
        ForEach(
            categoryFilters,
            content: categoryFilter
        )
    }
    
    private func categoryFilter(_ filter: NT_AccommodationCategoryFilter) -> some View {
        Text(title(filter))
            .tag(filter)
    }
}

// MARK: - Level of service filter picker:

private extension SortAndFilterTwoView {
    private var levelOfServiceFilterPicker: some View {
        levelOfServiceFilterPickerContent
            .pickerStyle(.navigationLink)
    }
    
    private var levelOfServiceFilterPickerContent: some View {
        Picker(selection: $levelOfServiceFilter) {
            levelOfServiceFiltersContent
        } label: {
            levelOfServiceFilterPickerLabel
        }
    }
    
    private var levelOfServiceFilterPickerLabel: some View {
        TitleSubtitleView(
            title: "Level of Service",
            subtitle: levelOfServiceFilterOptionsCount
        )
    }
    
    private var levelOfServiceFiltersContent: some View {
        ForEach(
            levelOfServiceFilters,
            content: levelOfServiceFilter
        )
    }
    
    private func levelOfServiceFilter(_ filter: NT_AccommodationLevelOfServiceFilter) -> some View {
        Text(title(filter))
            .tag(filter)
    }
}

// MARK: - Room type filter picker:

private extension SortAndFilterTwoView {
    private var roomTypeFilterPicker: some View {
        roomTypeFilterPickerContent
            .pickerStyle(.navigationLink)
    }
    
    private var roomTypeFilterPickerContent: some View {
        Picker(selection: $roomTypeFilter) {
            roomTypeFiltersContent
        } label: {
            roomTypeFilterPickerLabel
        }
    }
    
    private var roomTypeFilterPickerLabel: some View {
        TitleSubtitleView(
            title: "Room Type",
            subtitle: roomTypeFilterOptionsCount
        )
    }
    
    private var roomTypeFiltersContent: some View {
        ForEach(
            roomTypeFilters,
            content: roomTypeFilter
        )
    }
    
    private func roomTypeFilter(_ filter: NT_AccommodationRoomTypeFilter) -> some View {
        Text(title(filter))
            .tag(filter)
    }
}

// MARK: - Amenities filter picker:

private extension SortAndFilterTwoView {
    private var amenitiesFilterPicker: some View {
        amenitiesFilterPickerContent
            .pickerStyle(.navigationLink)
    }
    
    private var amenitiesFilterPickerContent: some View {
        Picker(selection: $amenitiesFilter) {
            amenitiesFiltersContent
        } label: {
            amenitiesFilterPickerLabel
        }
    }
    
    private var amenitiesFilterPickerLabel: some View {
        TitleSubtitleView(
            title: "Amenities",
            subtitle: amenitiesFilterOptionsCount
        )
    }
    
    private var amenitiesFiltersContent: some View {
        ForEach(
            amenitiesFilters,
            content: amenitiesFilter
        )
    }
    
    private func amenitiesFilter(_ filter: NT_AccommodationAmenitiesFilter) -> some View {
        Text(title(filter))
            .tag(filter)
    }
}

// MARK: - Wi-Fi filter picker:

private extension SortAndFilterTwoView {
    private var wiFiFilterPicker: some View {
        wiFiFilterPickerContent
            .pickerStyle(.navigationLink)
    }
    
    private var wiFiFilterPickerContent: some View {
        Picker(selection: $wiFiFilter) {
            wiFiFiltersContent
        } label: {
            wiFiFilterPickerLabel
        }
    }
    
    private var wiFiFilterPickerLabel: some View {
        TitleSubtitleView(
            title: "Wi-Fi Availability",
            subtitle: wiFiFilterOptionsCount
        )
    }
    
    private var wiFiFiltersContent: some View {
        ForEach(
            wiFiFilters,
            content: wiFiFilter
        )
    }
    
    private func wiFiFilter(_ filter: NT_AccommodationWiFiFilter) -> some View {
        Text(title(filter))
            .tag(filter)
    }
}

// MARK: - Airport shuttle service filter picker:

private extension SortAndFilterTwoView {
    private var airportShuttleServiceFilterPicker: some View {
        airportShuttleServiceFilterPickerContent
            .pickerStyle(.navigationLink)
    }
    
    private var airportShuttleServiceFilterPickerContent: some View {
        Picker(selection: $airportShuttleServiceFilter) {
            airportShuttleServiceFiltersContent
        } label: {
            airportShuttleServiceFilterPickerLabel
        }
    }
    
    private var airportShuttleServiceFilterPickerLabel: some View {
        TitleSubtitleView(
            title: "Airport Shuttle Service",
            subtitle: airportShuttleServiceFilterOptionsCount
        )
    }
    
    private var airportShuttleServiceFiltersContent: some View {
        ForEach(
            airportShuttleServiceFilters,
            content: airportShuttleServiceFilter
        )
    }
    
    private func airportShuttleServiceFilter(_ filter: NT_AccommodationAirportShuttleServiceFilter) -> some View {
        Text(title(filter))
            .tag(filter)
    }
}

// MARK: - Breakfast filter picker:

private extension SortAndFilterTwoView {
    private var breakfastFilterPicker: some View {
        breakfastFilterPickerContent
            .pickerStyle(.navigationLink)
    }
    
    private var breakfastFilterPickerContent: some View {
        Picker(selection: $breakfastFilter) {
            breakfastFiltersContent
        } label: {
            breakfastFilterPickerLabel
        }
    }
    
    private var breakfastFilterPickerLabel: some View {
        TitleSubtitleView(
            title: "Breakfast",
            subtitle: breakfastFilterOptionsCount
        )
    }
    
    private var breakfastFiltersContent: some View {
        ForEach(
            breakfastFilters,
            content: breakfastFilter
        )
    }
    
    private func breakfastFilter(_ filter: NT_AccommodationBreakfastFilter) -> some View {
        Text(title(filter))
            .tag(filter)
    }
}

// MARK: - Cancellation policy filter picker:

private extension SortAndFilterTwoView {
    private var cancellationPolicyFilterPicker: some View {
        cancellationPolicyFilterPickerContent
            .pickerStyle(.navigationLink)
    }
    
    private var cancellationPolicyFilterPickerContent: some View {
        Picker(selection: $cancellationPolicyFilter) {
            cancellationPolicyFiltersContent
        } label: {
            cancellationPolicyFilterPickerLabel
        }
    }
    
    private var cancellationPolicyFilterPickerLabel: some View {
        TitleSubtitleView(
            title: "Cancellation Policy",
            subtitle: cancellationPolicyFilterOptionsCount
        )
    }
    
    private var cancellationPolicyFiltersContent: some View {
        ForEach(
            cancellationPolicyFilters,
            content: cancellationPolicyFilter
        )
    }
    
    private func cancellationPolicyFilter(_ filter: NT_AccommodationCancellationPolicyFilter) -> some View {
        Text(title(filter))
            .tag(filter)
    }
}

// MARK: - Reviews filter picker:

private extension SortAndFilterTwoView {
    private var reviewsFilterPicker: some View {
        reviewsFilterPickerContent
            .pickerStyle(.navigationLink)
    }
    
    private var reviewsFilterPickerContent: some View {
        Picker(selection: $reviewsFilter) {
            reviewsFiltersContent
        } label: {
            reviewsFilterPickerLabel
        }
    }
    
    private var reviewsFilterPickerLabel: some View {
        TitleSubtitleView(
            title: "Reviews",
            subtitle: reviewsFilterOptionsCount
        )
    }
    
    private var reviewsFiltersContent: some View {
        ForEach(
            reviewsFilters,
            content: reviewsFilter
        )
    }
    
    private func reviewsFilter(_ filter: NT_AccommodationReviewsFilter) -> some View {
        Text(title(filter))
            .tag(filter)
    }
}

// MARK: - Toolbar:

private extension SortAndFilterTwoView {
    private var toolbar: some View {
        BottomToolbarView() {
            applyButton
        }
    }
    
    private var applyButton: some View {
        ButtonView(
            title: "Apply",
            action: apply
        )
    }
}

// MARK: - Preview:

#Preview {
    SortAndFilterTwoView()
}
