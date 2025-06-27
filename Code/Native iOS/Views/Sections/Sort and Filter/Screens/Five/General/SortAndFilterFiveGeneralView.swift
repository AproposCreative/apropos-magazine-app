//
//  SortAndFilterFiveGeneralView.swift
//  Native
//

import SwiftUI

struct SortAndFilterFiveGeneralView: View {
    
    // MARK: - Private properties:
    
    /// Category filter that is currently selected:
    @Binding private var selectedCategoryFilter: NT_ProductCategoryFilter
    
    /// Brand filter that is currently selected:
    @Binding private var selectedBrandFilter: NT_ProductBrandFilter
    
    /// 'Bool' value indicating whether or not the 'In Stock' filter is currently enabled:
    @Binding private var isInStock: Bool
    
    init(
        selectedCategoryFilter: Binding<NT_ProductCategoryFilter>,
        selectedBrandFilter: Binding<NT_ProductBrandFilter>,
        isInStock: Binding<Bool>
    ) {
        
        /// Properties initialization:
        _selectedCategoryFilter = selectedCategoryFilter
        _selectedBrandFilter = selectedBrandFilter
        _isInStock = isInStock
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

private extension SortAndFilterFiveGeneralView {
    private var item: some View {
        Section("General") {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        categoryFilterPicker
        brandFilterPicker
        inStockFilterToggle
    }
}

// MARK: - Category filter picker:

private extension SortAndFilterFiveGeneralView {
    private var categoryFilterPicker: some View {
        categoryFilterPickerContent
            .pickerStyle(.navigationLink)
    }
    
    private var categoryFilterPickerContent: some View {
        Picker(selection: $selectedCategoryFilter) {
            categoryFiltersContent
        } label: {
            label("Category")
        }
    }
    
    private var categoryFiltersContent: some View {
        ForEach(
            categoryFilters,
            content: categoryFilter
        )
    }
    
    private func categoryFilter(_ filter: NT_ProductCategoryFilter) -> some View {
        Text(title(filter))
            .tag(filter)
    }
}

// MARK: - Brand filter picker:

private extension SortAndFilterFiveGeneralView {
    private var brandFilterPicker: some View {
        brandFilterPickerContent
            .pickerStyle(.navigationLink)
    }
    
    private var brandFilterPickerContent: some View {
        Picker(selection: $selectedBrandFilter) {
            brandFiltersContent
        } label: {
            label("Brand")
        }
    }
    
    private var brandFiltersContent: some View {
        ForEach(
            brandFilters,
            content: brandFilter
        )
    }
    
    private func brandFilter(_ filter: NT_ProductBrandFilter) -> some View {
        Text(title(filter))
            .tag(filter)
    }
}

// MARK: - In stock filter toggle:

private extension SortAndFilterFiveGeneralView {
    private var inStockFilterToggle: some View {
        Toggle(isOn: $isInStock) {
            label("In Stock")
        }
    }
}

// MARK: - Label:

private extension SortAndFilterFiveGeneralView {
    private func label(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.headline)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.primary)
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var selectedCategoryFilter: NT_ProductCategoryFilter = .all
    @Previewable @State var selectedBrandFilter: NT_ProductBrandFilter = .all
    @Previewable @State var isInStock: Bool = true
    
    List {
        SortAndFilterFiveGeneralView(
            selectedCategoryFilter: $selectedCategoryFilter,
            selectedBrandFilter: $selectedBrandFilter,
            isInStock: $isInStock
        )
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(title: "Filter")
    .navigationStack()
}
