//
//  SortAndFilterOneSortView.swift
//  Native
//

import SwiftUI

struct SortAndFilterOneSortView: View {
    
    // MARK: - Private properties:
    
    /// Sort order that is currently selected:
    @Binding private var selectedSortOrder: NT_ProductSortOrder
    
    init(selectedSortOrder: Binding<NT_ProductSortOrder>) {
        
        /// Properties initialization:
        _selectedSortOrder = selectedSortOrder
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        Section {
            picker
        }
    }
}

// MARK: - Picker:

private extension SortAndFilterOneSortView {
    private var picker: some View {
        Picker(selection: $selectedSortOrder) {
            sortOrdersContent
        } label: {
            label
        }
    }
}

// MARK: - Sort orders:

private extension SortAndFilterOneSortView {
    private var sortOrdersContent: some View {
        ForEach(
            sortOrders,
            content: sortOrder
        )
    }
    
    private func sortOrder(_ sortOrder: NT_ProductSortOrder) -> some View {
        Text(title(sortOrder))
            .tag(sortOrder)
    }
}

// MARK: - Label:

private extension SortAndFilterOneSortView {
    private var label: some View {
        Text("Sort Order")
            .font(.headline)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.primary)
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var selectedSortOrder: NT_ProductSortOrder = .ascendingPrice
    
    List {
        SortAndFilterOneSortView(selectedSortOrder: $selectedSortOrder)
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(title: "Filter")
    .navigationStack()
}
