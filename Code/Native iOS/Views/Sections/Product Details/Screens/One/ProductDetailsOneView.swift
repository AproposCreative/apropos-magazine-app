//
//  ProductDetailsOneView.swift
//  Native
//

import SwiftUI

struct ProductDetailsOneView: View {
    
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

private extension ProductDetailsOneView {
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
        ProductDetailsOneToolbarView(product: product)
    }
}

// MARK: - Scroll:

private extension ProductDetailsOneView {
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
        thumbnail
        overview
        DividerView()
        ProductDetailsOneImagesView(product: product)
        DividerView()
        ProductDetailsOneReviewsView(product: product)
        DividerView()
        ProductDetailsOneFAQView(product: product)
    }
}

// MARK: - Thumbnail:

private extension ProductDetailsOneView {
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

// MARK: - Overview:

private extension ProductDetailsOneView {
    private var overview: some View {
        TitleSubtitleView(
            title: "Overview",
            titleFont: .title2.bold(),
            subtitle: longDescription,
            subtitleFont: .body,
            spacing: 12
        )
    }
}

// MARK: - Preview:

#Preview {
    ProductDetailsOneView(product: .example.first!)
}
