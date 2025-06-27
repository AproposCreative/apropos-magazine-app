//
//  ProductDetailsFiveYouMayAlsoLikeView.swift
//  Native
//

import SwiftUI

struct ProductDetailsFiveYouMayAlsoLikeView: View {
    
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

private extension ProductDetailsFiveYouMayAlsoLikeView {
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

private extension ProductDetailsFiveYouMayAlsoLikeView {
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

private extension ProductDetailsFiveYouMayAlsoLikeView {
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
            badgeBorderColor: backgroundColor,
            title: title(product),
            subtitle: blurb(product),
            backgroundColor: backgroundColor
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        ProductDetailsFiveYouMayAlsoLikeView(product: .example.first!)
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
