//
//  ProductDetailsFourView.swift
//  Native
//

import SwiftUI

struct ProductDetailsFourView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// An actual product to display the details for:
    let product: NT_Product
    
    // MARK: - Private properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) private var dismiss
    
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
            .localizedNavigationTitle(title: "Product Details")
            .toolbarButton(
                title: "Done",
                action: dismiss.callAsFunction
            )
            .navigationStack()
    }
}

// MARK: - Item:

private extension ProductDetailsFourView {
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
        scroll
        toolbar
    }
}

// MARK: - Scroll:

private extension ProductDetailsFourView {
    private var scroll: some View {
        scrollContent
            .safeAreaPadding(
                .all,
                16
            )
            .safeAreaPadding(
                .bottom,
                16
            )
    }
    
    private var scrollContent: some View {
        ScrollView {
            scrollItem
        }
    }
    
    private var scrollItem: some View {
        VStack(
            alignment: .leading,
            spacing: 32
        ) {
            scrollItemContent
        }
    }
    
    @ViewBuilder
    private var scrollItemContent: some View {
        thumbnail
        ProductDetailsFourKeyFeaturesView(product: product)
        ProductDetailsFourReviewsView(product: product)
    }
}

// MARK: - Thumbnail:

private extension ProductDetailsFourView {
    private var thumbnail: some View {
        TitleSubtitleBadgeImageBackgroundView(
            title: title,
            subtitle: blurb,
            badgeTitle: price,
            image: thumbnailImage,
            imageHeight: thumbnailImageHeight
        )
    }
}

// MARK: - Toolbar:

private extension ProductDetailsFourView {
    private var toolbar: some View {
        BottomToolbarView() {
            buyButton
        }
    }
    
    private var buyButton: some View {
        ButtonView(
            title: "Buy Now",
            action: buy
        )
    }
}

// MARK: - Preview:

#Preview {
    ProductDetailsFourView(product: .example.first!)
}
