//
//  SortAndFilterFiveView.swift
//  Native
//

import SwiftUI

struct SortAndFilterFiveView: View {
    
    // MARK: - Private properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) private var dismiss
    
    /// Category filter that is currently selected:
    @State private var categoryFilter: NT_ProductCategoryFilter = .all
    
    /// Brand filter that is currently selected:
    @State private var brandFilter: NT_ProductBrandFilter = .all
    
    /// 'Bool' value indicating whether or not the 'In Stock' filter is currently enabled:
    @State private var isInStock: Bool = true
    
    /// Price filter that is currently selected:
    @State private var priceFilter: Double = 100.0
    
    /// 'Bool' value indicating whether or not the 'Discount' filter is currently enabled:
    @State private var isDiscount: Bool = false
    
    /// 'Bool' value indicating whether or not the 'Free Shipping' filter is currently enabled:
    @State private var isFreeShipping: Bool = false
    
    /// Type filter that is currently selected:
    @State private var typeFilter: NT_AdditionalTypeFilter = .all
    
    /// Size filter that is currently selected:
    @State private var sizeFilter: Int = 1
    
    /// Color filter that is currently selected:
    @State private var colorFilter: NT_ProductColorFilter = .all
    
    /// Customization options filter that is currently selected:
    @State private var customizationOptionsFilter: NT_AdditionalCustomizationOptionsFilter = .none
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .localizedNavigationTitle(title: "Filter")
            .toolbarButton(
                title: "Done",
                action: dismiss.callAsFunction
            )
            .onChange(of: categoryFilter) { _, _ in
                triggerHapticFeedback()
            }
            .onChange(of: brandFilter) { _, _ in
                triggerHapticFeedback()
            }
            .onChange(of: typeFilter) { _, _ in
                triggerHapticFeedback()
            }
            .onChange(of: sizeFilter) { _, _ in
                triggerHapticFeedback()
            }
            .onChange(of: colorFilter) { _, _ in
                triggerHapticFeedback()
            }
            .onChange(of: customizationOptionsFilter) { _, _ in
                triggerHapticFeedback()
            }
            .navigationStack()
    }
}

// MARK: - Item:

private extension SortAndFilterFiveView {
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

private extension SortAndFilterFiveView {
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
        general
        price
        additional
    }
}

// MARK: - General:

private extension SortAndFilterFiveView {
    private var general: some View {
        SortAndFilterFiveGeneralView(
            selectedCategoryFilter: $categoryFilter,
            selectedBrandFilter: $brandFilter,
            isInStock: $isInStock
        )
    }
}

// MARK: - Price:

private extension SortAndFilterFiveView {
    private var price: some View {
        SortAndFilterFivePriceView(
            selectedPriceFilter: $priceFilter,
            isDiscount: $isDiscount
        )
    }
}

// MARK: - Additional:

private extension SortAndFilterFiveView {
    private var additional: some View {
        SortAndFilterFiveAdditionalView(
            isFreeShipping: $isFreeShipping,
            selectedTypeFilter: $typeFilter,
            selectedSizeFilter: $sizeFilter,
            selectedColorFilter: $colorFilter,
            selectedCustomizationOptionsFilter: $customizationOptionsFilter
        )
    }
}

// MARK: - Toolbar:

private extension SortAndFilterFiveView {
    private var toolbar: some View {
        BottomToolbarView(
            spacing: 8,
            backgroundColor: .init(.systemGroupedBackground)
        ) {
            applyClearAllButtons
        }
    }
    
    @ViewBuilder
    private var applyClearAllButtons: some View {
        applyButton
        clearAllButton
    }
    
    private var applyButton: some View {
        ButtonView(
            title: "Apply",
            action: apply
        )
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
}

// MARK: - Preview:

#Preview {
    SortAndFilterFiveView()
}
