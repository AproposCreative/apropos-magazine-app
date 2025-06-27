//
//  SortAndFilterOneFilterView.swift
//  Native
//

import SwiftUI

struct SortAndFilterOneFilterView: View {
    
    // MARK: - Private properties:
    
    /// Category filter that is currently selected:
    @Binding private var selectedCategoryFilter: NT_ProductCategoryFilter
    
    /// Brand filter that is currently selected:
    @Binding private var selectedBrandFilter: NT_ProductBrandFilter
    
    /// Processor filter that is currently selected:
    @Binding private var selectedProcessorFilter: NT_ProductProcessorFilter
    
    /// RAM filter that is currently selected:
    @Binding private var selectedRAMFilter: NT_ProductRAMFilter
    
    /// Storage filter that is currently selected:
    @Binding private var selectedStorageFilter: NT_ProductStorageFilter
    
    /// Color filter that is currently selected:
    @Binding private var selectedColorFilter: NT_ProductColorFilter
    
    init(
        selectedCategoryFilter: Binding<NT_ProductCategoryFilter>,
        selectedBrandFilter: Binding<NT_ProductBrandFilter>,
        selectedProcessorFilter: Binding<NT_ProductProcessorFilter>,
        selectedRAMFilter: Binding<NT_ProductRAMFilter>,
        selectedStorageFilter: Binding<NT_ProductStorageFilter>,
        selectedColorFilter: Binding<NT_ProductColorFilter>
    ) {
        
        /// Properties initialization:
        _selectedCategoryFilter = selectedCategoryFilter
        _selectedBrandFilter = selectedBrandFilter
        _selectedProcessorFilter = selectedProcessorFilter
        _selectedRAMFilter = selectedRAMFilter
        _selectedStorageFilter = selectedStorageFilter
        _selectedColorFilter = selectedColorFilter
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

private extension SortAndFilterOneFilterView {
    private var item: some View {
        Section("Filter By") {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        categoryFilterPicker
        brandFilterPicker
        processorFilterPicker
        ramFilterPicker
        storageFilterPicker
        colorFilterPicker
    }
}

// MARK: - Category filter picker:

private extension SortAndFilterOneFilterView {
    private var categoryFilterPicker: some View {
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

private extension SortAndFilterOneFilterView {
    private var brandFilterPicker: some View {
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

// MARK: - Processor filter picker:

private extension SortAndFilterOneFilterView {
    private var processorFilterPicker: some View {
        Picker(selection: $selectedProcessorFilter) {
            processorFiltersContent
        } label: {
            label("Processor")
        }
    }
    
    private var processorFiltersContent: some View {
        ForEach(
            processorFilters,
            content: processorFilter
        )
    }
    
    private func processorFilter(_ filter: NT_ProductProcessorFilter) -> some View {
        Text(title(filter))
            .tag(filter)
    }
}

// MARK: - RAM filter picker:

private extension SortAndFilterOneFilterView {
    private var ramFilterPicker: some View {
        Picker(selection: $selectedRAMFilter) {
            ramFiltersContent
        } label: {
            label("RAM")
        }
    }
    
    private var ramFiltersContent: some View {
        ForEach(
            ramFilters,
            content: ramFilter
        )
    }
    
    private func ramFilter(_ filter: NT_ProductRAMFilter) -> some View {
        Text(title(filter))
            .tag(filter)
    }
}

// MARK: - Storage filter picker:

private extension SortAndFilterOneFilterView {
    private var storageFilterPicker: some View {
        Picker(selection: $selectedStorageFilter) {
            storageFiltersContent
        } label: {
            label("Storage")
        }
    }
    
    private var storageFiltersContent: some View {
        ForEach(
            storageFilters,
            content: storageFilter
        )
    }
    
    private func storageFilter(_ filter: NT_ProductStorageFilter) -> some View {
        Text(title(filter))
            .tag(filter)
    }
}

// MARK: - Color filter picker:

private extension SortAndFilterOneFilterView {
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

// MARK: - Label:

private extension SortAndFilterOneFilterView {
    private func label(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.headline)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.primary)
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var selectedCategoryFilter: NT_ProductCategoryFilter = .laptop
    @Previewable @State var selectedBrandFilter: NT_ProductBrandFilter = .apple
    @Previewable @State var selectedProcessorFilter: NT_ProductProcessorFilter = .appleM3Max
    @Previewable @State var selectedRAMFilter: NT_ProductRAMFilter = .fortyEightGB
    @Previewable @State var selectedStorageFilter: NT_ProductStorageFilter = .twoTB
    @Previewable @State var selectedColorFilter: NT_ProductColorFilter = .spaceBlack
    
    List {
        SortAndFilterOneFilterView(
            selectedCategoryFilter: $selectedCategoryFilter,
            selectedBrandFilter: $selectedBrandFilter,
            selectedProcessorFilter: $selectedProcessorFilter,
            selectedRAMFilter: $selectedRAMFilter,
            selectedStorageFilter: $selectedStorageFilter,
            selectedColorFilter: $selectedColorFilter
        )
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(title: "Filter")
    .navigationStack()
}
