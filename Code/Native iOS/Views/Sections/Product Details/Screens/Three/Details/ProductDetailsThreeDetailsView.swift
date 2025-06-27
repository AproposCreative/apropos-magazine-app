//
//  ProductDetailsThreeDetailsView.swift
//  Native
//

import SwiftUI

struct ProductDetailsThreeDetailsView: View {
    
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

private extension ProductDetailsThreeDetailsView {
    @ViewBuilder
    private var item: some View {
        thumbnailImageContent
        details
    }
}

// MARK: - Thumbnail image content:

private extension ProductDetailsThreeDetailsView {
    private var thumbnailImageContent: some View {
        ImageBackgroundView(
            image: thumbnailImage,
            height: 224,
            isShowingBackground: false,
            cornerRadius: 16,
            accessibilityLabel: "Product image"
        )
    }
}

// MARK: - Details:

private extension ProductDetailsThreeDetailsView {
    private var details: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            detailsContent
        }
    }
    
    @ViewBuilder
    private var detailsContent: some View {
        detailsHeader
        longDescriptionContent
    }
    
    @ViewBuilder
    private var detailsHeader: some View {
        if shouldMoveContent {
            headerContent
        } else {
            header
        }
    }
}

// MARK: - Header:

private extension ProductDetailsThreeDetailsView {
    private var header: some View {
        HStack(
            alignment: .top,
            spacing: 12
        ) {
            headerContent
        }
    }
    
    @ViewBuilder
    private var headerContent: some View {
        titleContent
        priceContent
    }
    
    private var titleContent: some View {
        Text(title)
            .font(.title2.bold())
            .multilineTextAlignment(.leading)
            .foregroundStyle(.primary)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
    }
    
    private var priceContent: some View {
        BadgeView(
            title: price,
            size: .small
        )
    }
}

// MARK: - Long description:

private extension ProductDetailsThreeDetailsView {
    private var longDescriptionContent: some View {
        Text(longDescription)
            .font(.body)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        ProductDetailsThreeDetailsView(product: .example.first!)
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
