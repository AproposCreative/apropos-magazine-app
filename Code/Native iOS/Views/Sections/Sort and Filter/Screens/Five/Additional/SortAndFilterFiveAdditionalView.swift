//
//  SortAndFilterFiveAdditionalView.swift
//  Native
//

import SwiftUI

struct SortAndFilterFiveAdditionalView: View {
    
    // MARK: - Private properties:
    
    /// 'Bool' value indicating whether or not the 'Free Shipping' filter is currently enabled:
    @Binding private var isFreeShipping: Bool
    
    /// Type filter that is currently selected:
    @Binding private var selectedTypeFilter: NT_AdditionalTypeFilter
    
    /// Size filter that is currently selected:
    @Binding private var selectedSizeFilter: Int
    
    /// Color filter that is currently selected:
    @Binding private var selectedColorFilter: NT_ProductColorFilter
    
    /// Customization options filter that is currently selected:
    @Binding private var selectedCustomizationOptionsFilter: NT_AdditionalCustomizationOptionsFilter
    
    init(
        isFreeShipping: Binding<Bool>,
        selectedTypeFilter: Binding<NT_AdditionalTypeFilter>,
        selectedSizeFilter: Binding<Int>,
        selectedColorFilter: Binding<NT_ProductColorFilter>,
        selectedCustomizationOptionsFilter: Binding<NT_AdditionalCustomizationOptionsFilter>
    ) {
        
        /// Properties initialization:
        _isFreeShipping = isFreeShipping
        _selectedTypeFilter = selectedTypeFilter
        _selectedSizeFilter = selectedSizeFilter
        _selectedColorFilter = selectedColorFilter
        _selectedCustomizationOptionsFilter = selectedCustomizationOptionsFilter
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .headerProminence(.increased)
    }
}

// MARK: - Item:

private extension SortAndFilterFiveAdditionalView {
    private var item: some View {
        Section("Additional") {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        freeShippingFilterToggle
        typeFilterPicker
        sizeFilterStepper
        colorFilterPicker
        reviews
        customizationOptionsFilterPicker
    }
}

// MARK: - Free shipping filter toggle:

private extension SortAndFilterFiveAdditionalView {
    private var freeShippingFilterToggle: some View {
        Toggle(isOn: $isFreeShipping) {
            label("Free Shipping")
        }
    }
}

// MARK: - Type filter picker:

private extension SortAndFilterFiveAdditionalView {
    private var typeFilterPicker: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            typeFilterPickerContent
        }
    }
    
    @ViewBuilder
    private var typeFilterPickerContent: some View {
        label(typeFilterPickerTitle)
        typeFilterPickerItem
    }
    
    private var typeFilterPickerItem: some View {
        typeFilterPickerItemContent
            .pickerStyle(.segmented)
            .labelsHidden()
    }
    
    private var typeFilterPickerItemContent: some View {
        Picker(
            typeFilterPickerTitle,
            selection: $selectedTypeFilter
        ) {
            typeFiltersContent
        }
    }
    
    private var typeFiltersContent: some View {
        ForEach(
            typeFilters,
            content: typeFilter
        )
    }
    
    private func typeFilter(_ filter: NT_AdditionalTypeFilter) -> some View {
        Text(title(filter))
            .tag(filter)
    }
}

// MARK: - Size filter stepper:

private extension SortAndFilterFiveAdditionalView {
    private var sizeFilterStepper: some View {
        Stepper(
            value: $selectedSizeFilter,
            in: sizeRange
        ) {
            label("Size")
        }
    }
}

// MARK: - Color filter picker:

private extension SortAndFilterFiveAdditionalView {
    private var colorFilterPicker: some View {
        Picker(selection: $selectedColorFilter) {
            colorFiltersContent
        } label: {
            label("Color")
        }
    }
    
    private var colorFiltersContent: some View {
        ForEach(
            colorFilters,
            content: colorFilter
        )
    }
    
    private func colorFilter(_ filter: NT_ProductColorFilter) -> some View {
        Text(title(filter))
            .tag(filter)
    }
}

// MARK: - Reviews:

private extension SortAndFilterFiveAdditionalView {
    private var reviews: some View {
        NavigationLink {
            PlaceholderView(title: reviewsTitle)
        } label: {
            label(.init(reviewsTitle))
        }
    }
}

// MARK: - Customization options filter picker:

private extension SortAndFilterFiveAdditionalView {
    private var customizationOptionsFilterPicker: some View {
        customizationOptionsFilterPickerContent
            .pickerStyle(.navigationLink)
    }
    
    private var customizationOptionsFilterPickerContent: some View {
        Picker(selection: $selectedCustomizationOptionsFilter) {
            customizationOptionsFiltersContent
        } label: {
            label("Customization Options")
        }
    }
    
    private var customizationOptionsFiltersContent: some View {
        ForEach(
            customizationOptionsFilters,
            content: customizationOptionsFilter
        )
    }
    
    private func customizationOptionsFilter(_ filter: NT_AdditionalCustomizationOptionsFilter) -> some View {
        Text(title(filter))
            .tag(filter)
    }
}

// MARK: - Label:

private extension SortAndFilterFiveAdditionalView {
    private func label(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.headline)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.primary)
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var isFreeShipping: Bool = false
    @Previewable @State var selectedTypeFilter: NT_AdditionalTypeFilter = .all
    @Previewable @State var selectedSizeFilter: Int = 0
    @Previewable @State var selectedColorFilter: NT_ProductColorFilter = .all
    @Previewable @State var selectedCustomizationOptionsFilter: NT_AdditionalCustomizationOptionsFilter = .none
    
    List {
        SortAndFilterFiveAdditionalView(
            isFreeShipping: $isFreeShipping,
            selectedTypeFilter: $selectedTypeFilter,
            selectedSizeFilter: $selectedSizeFilter,
            selectedColorFilter: $selectedColorFilter,
            selectedCustomizationOptionsFilter: $selectedCustomizationOptionsFilter
        )
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(title: "Filter")
    .navigationStack()
}
