//
//  SortAndFilterOneView.swift
//  Native
//

import SwiftUI

struct SortAndFilterOneView: View {
    
    // MARK: - Private properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) private var dismiss
    
    /// Sort order that is currently selected:
    @State private var sortOrder: NT_ProductSortOrder = .ascendingPrice
    
    /// Category filter that is currently selected:
    @State private var categoryFilter: NT_ProductCategoryFilter = .laptop
    
    /// Brand filter that is currently selected:
    @State private var brandFilter: NT_ProductBrandFilter = .apple
    
    /// Processor filter that is currently selected:
    @State private var processorFilter: NT_ProductProcessorFilter = .appleM3Max
    
    /// RAM filter that is currently selected:
    @State private var ramFilter: NT_ProductRAMFilter = .fortyEightGB
    
    /// Storage filter that is currently selected:
    @State private var storageFilter: NT_ProductStorageFilter = .twoTB
    
    /// Color filter that is currently selected:
    @State private var colorFilter: NT_ProductColorFilter = .spaceBlack
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .localizedNavigationTitle(title: "Filter")
            .toolbarButton(
                title: "Dismiss",
                icon: Icons.xmarkCircle,
                font: .body,
                color: .init(.tertiaryLabel),
                style: .iconOnly,
                placement: .cancellationAction,
                action: dismiss.callAsFunction
            )
            .onChange(of: sortOrder) { _, _ in
                triggerHapticFeedback()
            }
            .onChange(of: categoryFilter) { _, _ in
                triggerHapticFeedback()
            }
            .onChange(of: brandFilter) { _, _ in
                triggerHapticFeedback()
            }
            .onChange(of: processorFilter) { _, _ in
                triggerHapticFeedback()
            }
            .onChange(of: ramFilter) { _, _ in
                triggerHapticFeedback()
            }
            .onChange(of: storageFilter) { _, _ in
                triggerHapticFeedback()
            }
            .onChange(of: colorFilter) { _, _ in
                triggerHapticFeedback()
            }
            .navigationStack()
    }
}

// MARK: - Item:

private extension SortAndFilterOneView {
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
        listContent
        toolbar
    }
}

// MARK: - List:

private extension SortAndFilterOneView {
    private var list: some View {
        listContent
            .listStyle(.insetGrouped)
    }
    
    private var listContent: some View {
        List {
            listItem
        }
    }
    
    @ViewBuilder
    private var listItem: some View {
        SortAndFilterOneSortView(selectedSortOrder: $sortOrder)
        filter
    }
}

// MARK: - Filter:

private extension SortAndFilterOneView {
    private var filter: some View {
        SortAndFilterOneFilterView(
            selectedCategoryFilter: $categoryFilter,
            selectedBrandFilter: $brandFilter,
            selectedProcessorFilter: $processorFilter,
            selectedRAMFilter: $ramFilter,
            selectedStorageFilter: $storageFilter,
            selectedColorFilter: $colorFilter
        )
    }
}

// MARK: - Toolbar:

private extension SortAndFilterOneView {
    private var toolbar: some View {
        BottomToolbarView(
            spacing: 8,
            contentAlignment: .horizontal,
            backgroundColor: .init(.systemGroupedBackground)
        ) {
            clearAllApplyButtons
        }
    }
    
    @ViewBuilder
    private var clearAllApplyButtons: some View {
        clearAllButton
        applyButton
    }
    
    private var clearAllButton: some View {
        ButtonView(
            title: "Clear All",
            titleColor: .primary,
            backgroundColor: .init(.secondarySystemGroupedBackground),
            isBackgroundColorGradient: false,
            action: clearAll
        )
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
    SortAndFilterOneView()
}
