//
//  SortAndFilterFivePriceView.swift
//  Native
//

import SwiftUI

struct SortAndFilterFivePriceView: View {
    
    // MARK: - Private properties:
    
    /// Price filter that is currently selected:
    @Binding private var selectedPriceFilter: Double
    
    /// 'Bool' value indicating whether or not the 'Discount' filter is currently enabled:
    @Binding private var isDiscount: Bool
    
    init(
        selectedPriceFilter: Binding<Double>,
        isDiscount: Binding<Bool>
    ) {
        
        /// Properties initialization:
        _selectedPriceFilter = selectedPriceFilter
        _isDiscount = isDiscount
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

private extension SortAndFilterFivePriceView {
    private var item: some View {
        Section("Price") {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        priceFilterSlider
        discountFilterToggle
    }
}

// MARK: - Price filter slider:

private extension SortAndFilterFivePriceView {
    private var priceFilterSlider: some View {
        Slider(
            value: $selectedPriceFilter,
            in: priceRange
        ) {
            label("Price")
        } minimumValueLabel: {
            priceFilterSliderLabel(Icons.dollarsign)
        } maximumValueLabel: {
            priceFilterSliderLabel(Icons.dollarsign)
        }
    }
    
    private func priceFilterSliderLabel(_ icon: String) -> some View {
        Image(systemName: icon)
            .symbolVariant(.fill)
            .font(priceFilterSliderIconFont)
            .foregroundStyle(.secondary)
            .frame(
                width: priceFilterSliderLabelFrame,
                height: priceFilterSliderLabelFrame,
                alignment: .center
            )
            .accessibilityElement(children: .ignore)
    }
}

// MARK: - Discount filter toggle:

private extension SortAndFilterFivePriceView {
    private var discountFilterToggle: some View {
        Toggle(isOn: $isDiscount) {
            label("Discount")
        }
    }
}

// MARK: - Label:

private extension SortAndFilterFivePriceView {
    private func label(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.headline)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.primary)
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var selectedPriceFilter: Double = 100.00
    @Previewable @State var isDiscount: Bool = false
    
    List {
        SortAndFilterFivePriceView(
            selectedPriceFilter: $selectedPriceFilter,
            isDiscount: $isDiscount
        )
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(title: "Filter")
    .navigationStack()
}
