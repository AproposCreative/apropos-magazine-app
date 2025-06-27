//
//  ProductDetailsFiveDetailsView.swift
//  Native
//

import SwiftUI

struct ProductDetailsFiveDetailsView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
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
        VStack(
            alignment: .leading,
            spacing: 24
        ) {
            item
        }
    }
}

// MARK: - Item:

private extension ProductDetailsFiveDetailsView {
    @ViewBuilder
    private var item: some View {
        thumbnailImageContent
        details
    }
}

// MARK: - Thumbnail image content:

private extension ProductDetailsFiveDetailsView {
    private var thumbnailImageContent: some View {
        ImageBackgroundBadgeView(
            image: thumbnailImage,
            imageWidth: 304,
            imageHeight: thumbnailImageHeight,
            imageCornerRadius: 16,
            imageAccessibilityLabel: "Product image",
            badgeTitle: price,
            badgeXAxisOffset: thumbnailImageBadgeOffset,
            badgeYAxisOffset: thumbnailImageBadgeOffset
        )
    }
}

// MARK: - Details:

private extension ProductDetailsFiveDetailsView {
    private var details: some View {
        TitleSubtitleView(
            title: title,
            titleFont: .title2.bold(),
            subtitle: longDescription,
            subtitleFont: .body,
            spacing: 12
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        ProductDetailsFiveDetailsView(product: .example.first!)
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
