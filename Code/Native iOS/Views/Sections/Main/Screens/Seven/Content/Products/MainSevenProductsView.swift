//
//  MainSevenProductsView.swift
//  Native
//

import SwiftUI

struct MainSevenProductsView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// An array of the products to display:
    let products: [NT_Product]
    
    // MARK: - Private properties:
    
    /// Namespace that is needed for the zoom transition:
    @Namespace private var namespace
    
    init(products: [NT_Product]) {
        
        /// Properties initialization:
        self.products = products
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

private extension MainSevenProductsView {
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
        SectionHeaderView(title: "Popular Products")
        productsContent
    }
}

// MARK: - Products:

private extension MainSevenProductsView {
    private var productsContent: some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading,
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
            .matchedTransitionSource(
                id: identifier(product),
                in: namespace
            )
    }
    
    private func productContent(_ product: NT_Product) -> some View {
        NavigationLink {
            productItem(product)
        } label: {
            productLabel(product)
        }
    }
    
    private func productItem(_ product: NT_Product) -> some View {
        PlaceholderView(title: title(product))
            .navigationTransition(
                .zoom(
                    sourceID: identifier(product),
                    in: namespace
                )
            )
    }
    
    private func productLabel(_ product: NT_Product) -> some View {
        ImageBackgroundBadgeTitleSubtitleView(
            image: smallThumbnailImage(product),
            imageHeight: imageHeight,
            isShowingImageBackground: false,
            imageCornerRadius: 12,
            badgeTitle: price(product),
            title: title(product),
            isShowingSubtitle: doesHaveShortDescription(product),
            subtitle: shortDescription(product),
            titleSubtitleSpacing: 4,
            spacing: 12,
            maxHeight: .infinity
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        MainSevenProductsView(products: NT_Product.example)
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
    .localizedNavigationTitle(title: "Explore")
    .navigationDestination(for: NT_Product.self) { product in
        PlaceholderView(title: product.title)
    }
    .navigationStack()
}
