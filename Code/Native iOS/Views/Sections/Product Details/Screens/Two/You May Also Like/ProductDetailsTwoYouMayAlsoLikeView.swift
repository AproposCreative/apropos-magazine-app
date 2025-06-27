//
//  ProductDetailsTwoYouMayAlsoLikeView.swift
//  Native
//

import SwiftUI

struct ProductDetailsTwoYouMayAlsoLikeView: View {
    
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
    
    @ViewBuilder
    private var content: some View {
        if isShowing {
            item
        }
    }
}

// MARK: - Item:

private extension ProductDetailsTwoYouMayAlsoLikeView {
    private var item: some View {
        VStack(
            alignment: .leading,
            spacing: spacing
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        SectionHeaderView(title: "You May Also Like")
        scroll
    }
}

// MARK: - Scroll:

private extension ProductDetailsTwoYouMayAlsoLikeView {
    private var scroll: some View {
        scrollContent
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
    }
    
    private var scrollContent: some View {
        ScrollView(.horizontal) {
            scrollItem
        }
    }
    
    private var scrollItem: some View {
        productsContent
            .scrollTargetLayout()
    }
}

// MARK: - Products:

private extension ProductDetailsTwoYouMayAlsoLikeView {
    private var productsContent: some View {
        LazyHStack(
            alignment: .top,
            spacing: spacing
        ) {
            productsItem
        }
    }
    
    private var productsItem: some View {
        ForEach(
            products,
            content: product
        )
    }
    
    private func product(_ product: NT_Product) -> some View {
        productContent(product)
            .frame(
                width: 328,
                alignment: .leading
            )
    }
    
    private func productContent(_ product: NT_Product) -> some View {
        ImageBackgroundBadgeTitleSubtitleView(
            image: thumbnailImage(product),
            imageHeight: thumbnailImageHeight,
            badgeTitle: price(product),
            title: title(product),
            subtitle: blurb(product)
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        ProductDetailsTwoYouMayAlsoLikeView(product: .example.first!)
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .background(Color(.systemGroupedBackground))
    .localizedNavigationTitle(title: "Product Details")
    .navigationStack()
}
