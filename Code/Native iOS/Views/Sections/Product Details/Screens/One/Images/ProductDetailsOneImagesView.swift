//
//  ProductDetailsOneImagesView.swift
//  Native
//

import SwiftUI

struct ProductDetailsOneImagesView: View {
    
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

private extension ProductDetailsOneImagesView {
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
        SectionHeaderView(title: "Images")
        scroll
    }
}

// MARK: - Scroll:

private extension ProductDetailsOneImagesView {
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
        imagesContent
            .scrollTargetLayout()
    }
}

// MARK: - Images:

private extension ProductDetailsOneImagesView {
    private var imagesContent: some View {
        LazyHStack(
            alignment: .top,
            spacing: spacing
        ) {
            imagesItem
        }
    }
    
    private var imagesItem: some View {
        ForEach(
            images,
            content: image
        )
    }
    
    private func image(_ image: NT_Image) -> some View {
        ImageBackgroundView(
            image: imageContent(image),
            width: 328,
            height: 224,
            isFullWidth: false,
            isShowingBackground: false,
            cornerRadius: 16,
            accessibilityLabel: accessibilityLabel(image)
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        ProductDetailsOneImagesView(product: .example.first!)
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
