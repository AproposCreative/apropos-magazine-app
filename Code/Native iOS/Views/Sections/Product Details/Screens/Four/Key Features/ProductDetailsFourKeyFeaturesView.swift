//
//  ProductDetailsFourKeyFeaturesView.swift
//  Native
//

import SwiftUI

struct ProductDetailsFourKeyFeaturesView: View {
    
    // MARK: - Properties:
    
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
    
    @ViewBuilder
    private var content: some View {
        if isShowing {
            item
        }
    }
}

// MARK: - Item:

private extension ProductDetailsFourKeyFeaturesView {
    private var item: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        SectionHeaderView(title: "Key Features")
        keyFeaturesContent
    }
}

// MARK: - Key features:

private extension ProductDetailsFourKeyFeaturesView {
    private var keyFeaturesContent: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            keyFeaturesItem
        }
    }
    
    private var keyFeaturesItem: some View {
        ForEach(
            keyFeatures,
            content: keyFeature
        )
    }
    
    private func keyFeature(_ keyFeature: NT_ProductKeyFeature) -> some View {
        TitleValueView(
            title: title(keyFeature),
            value: value(keyFeature),
            isShowingTopDivider: isShowingTopDivider(keyFeature)
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        ProductDetailsFourKeyFeaturesView(product: .example.first!)
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .localizedNavigationTitle(title: "Product Details")
    .navigationStack()
}
