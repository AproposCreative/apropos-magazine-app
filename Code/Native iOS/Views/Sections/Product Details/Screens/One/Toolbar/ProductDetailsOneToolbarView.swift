//
//  ProductDetailsOneToolbarView.swift
//  Native
//

import SwiftUI

struct ProductDetailsOneToolbarView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// Storage option that is currently selected:
    @State var selectedStorage: NT_ProductStorage? = nil
    
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
                value: selectedStorage
            )
    }
}

// MARK: - Item:

private extension ProductDetailsOneToolbarView {
    private var item: some View {
        BottomToolbarView(spacing: spacing) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        storagesContent
        buyButton
    }
}

// MARK: - Storages:

private extension ProductDetailsOneToolbarView {
    @ViewBuilder
    private var storagesContent: some View {
        if isShowingStorages {
            storagesItem
        }
    }
    
    private var storagesItem: some View {
        VStack(
            alignment: .leading,
            spacing: spacing
        ) {
            storagesItemContent
        }
    }
    
    @ViewBuilder
    private var storagesItemContent: some View {
        storagesHeader
        storagesItems
    }
    
    private var storagesHeader: some View {
        SectionHeaderView(
            title: "Storage",
            titleFont: .headline
        )
    }
    
    @ViewBuilder
    private var storagesItems: some View {
        if shouldMoveContent {
            verticalStoragesItemsContent
        } else {
            horizontalStoragesItemsContent
        }
    }
    
    private var horizontalStoragesItemsContent: some View {
        HStack(
            alignment: .top,
            spacing: spacing
        ) {
            storagesItemsItem
        }
    }
    
    private var verticalStoragesItemsContent: some View {
        VStack(
            alignment: .leading,
            spacing: spacing
        ) {
            storagesItemsItem
        }
    }
    
    private var storagesItemsItem: some View {
        ForEach(
            storages,
            content: storage
        )
    }
    
    private func storage(_ storage: NT_ProductStorage) -> some View {
        SelectButtonTitleSubtitleView(
            isSelected: isSelected(storage),
            title: title(storage),
            isShowingSubtitle: false,
            subtitle: "",
            isReversed: true,
            backgroundColor: .init(.systemBackground),
            borderWidth: borderWidth(storage),
            borderColor: borderColor(storage),
            isBorderGradient: isSelected(storage)
        ) {
            select(storage)
        }
    }
}

// MARK: - Buy button:

private extension ProductDetailsOneToolbarView {
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
        
        ProductDetailsOneToolbarView(product: .example.first!)
    }
}
