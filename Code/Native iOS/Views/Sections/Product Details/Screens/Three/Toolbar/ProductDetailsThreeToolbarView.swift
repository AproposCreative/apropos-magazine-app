//
//  ProductDetailsThreeToolbarView.swift
//  Native
//

import SwiftUI

struct ProductDetailsThreeToolbarView: View {
    
    // MARK: - Properties:
    
    /// Color option that is currently selected:
    @State var selectedColor: NT_Color? = nil
    
    /// An actual product to display the details for:
    let product: NT_Product
    
    init(product: NT_Product) {
        
        /// Properties initialization:
        self.product = product
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .animation(
                .default,
                value: selectedColor
            )
    }
}

// MARK: - Item:

private extension ProductDetailsThreeToolbarView {
    private var item: some View {
        BottomToolbarView(backgroundColor: .init(.systemGroupedBackground)) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        title
        colorsContent
        buyButton
    }
}

// MARK: - Title:

private extension ProductDetailsThreeToolbarView {
    private var title: some View {
        Text("Color")
            .font(.headline)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.primary)
    }
}

// MARK: - Colors:

private extension ProductDetailsThreeToolbarView {
    @ViewBuilder
    private var colorsContent: some View {
        if isShowingColors {
            colorsItem
        }
    }
    
    private var colorsItem: some View {
        ColorPickerView(
            selectedColor: $selectedColor,
            colors: colors,
            spacing: 4,
            verticalPadding: 0,
            horizontalPadding: 0,
            isShowingBackground: false,
            cornerRadius: 0
        )
    }
}

// MARK: - Buy button:

private extension ProductDetailsThreeToolbarView {
    private var buyButton: some View {
        ButtonView(
            title: "Buy Now",
            isDisabled: isBuyDisabled,
            action: buy
        )
    }
}

// MARK: - Preview:

#Preview {
    VStack(
        alignment: .leading,
        spacing: 0
    ) {
        ScrollView {  }
        
        ProductDetailsThreeToolbarView(product: .example.first!)
    }
    .background(Color(.systemGroupedBackground))
}
