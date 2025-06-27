//
//  ProductDetailsFiveView.swift
//  Native
//

import SwiftUI

struct ProductDetailsFiveView: View {
    
    // MARK: - Properties:
    
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

private extension ProductDetailsFiveView {
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

private extension ProductDetailsFiveView {
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
            spacing: 24
        ) {
            scrollItemContent
        }
    }
    
    @ViewBuilder
    private var scrollItemContent: some View {
        ProductDetailsFiveDetailsView(product: product)
        DividerView()
        ProductDetailsFiveReviewsView(product: product)
        DividerView()
        ProductDetailsFiveFAQView(product: product)
        DividerView()
        ProductDetailsFiveYouMayAlsoLikeView(product: product)
    }
}

// MARK: - Toolbar:

private extension ProductDetailsFiveView {
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
    ProductDetailsFiveView(product: .example.first!)
}
