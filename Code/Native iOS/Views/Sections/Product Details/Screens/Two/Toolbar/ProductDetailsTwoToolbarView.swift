//
//  ProductDetailsTwoToolbarView.swift
//  Native
//

import SwiftUI

struct ProductDetailsTwoToolbarView: View {
    
    // MARK: - Properties:
    
    /// Configuration option that is currently selected:
    @State var selectedConfiguration: NT_ProductConfiguration? = nil
    
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
                value: selectedConfiguration
            )
    }
}

// MARK: - Item:

private extension ProductDetailsTwoToolbarView {
    private var item: some View {
        BottomToolbarView(
            spacing: spacing,
            backgroundColor: .init(.systemGroupedBackground)
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        configurationsContent
        buyButton
    }
}

// MARK: - Configurations:

private extension ProductDetailsTwoToolbarView {
    @ViewBuilder
    private var configurationsContent: some View {
        if isShowingConfigurations {
            configurationsItem
        }
    }
    
    private var configurationsItem: some View {
        VStack(
            alignment: .leading,
            spacing: spacing
        ) {
            configurationsItemContent
        }
    }
    
    @ViewBuilder
    private var configurationsItemContent: some View {
        configurationsHeader
        configurationsItems
    }
    
    private var configurationsHeader: some View {
        SectionHeaderView(
            title: "Configuration",
            titleFont: .headline
        )
    }
    
    private var configurationsItems: some View {
        VStack(
            alignment: .leading,
            spacing: spacing
        ) {
            configurationsItemsContent
        }
    }
    
    private var configurationsItemsContent: some View {
        ForEach(
            configurations,
            content: configuration
        )
    }
    
    private func configuration(_ configuration: NT_ProductConfiguration) -> some View {
        SelectButtonTitleSubtitleView(
            isSelected: isSelected(configuration),
            title: title(configuration),
            subtitle: description(configuration),
            borderWidth: borderWidth(configuration),
            borderColor: borderColor(configuration),
            isBorderGradient: isSelected(configuration)
        ) {
            select(configuration)
        }
    }
}

// MARK: - Buy button:

private extension ProductDetailsTwoToolbarView {
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
        
        ProductDetailsTwoToolbarView(product: .example.first!)
    }
    .background(Color(.systemGroupedBackground))
}
