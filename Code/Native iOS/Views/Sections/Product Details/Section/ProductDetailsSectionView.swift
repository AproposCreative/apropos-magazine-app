//
//  ProductDetailsSectionView.swift
//  Native
//

import SwiftUI

struct ProductDetailsSectionView: View {
    
    // MARK: - Properties:
    
    /// Screen that is currently shown (Can be 'nil' or no screen at all):
    @State var currentScreen: NT_ProductDetailsScreen? = nil
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        list
            .navigationTitle("Product Details")
            .sheet(
                item: $currentScreen,
                content: showScreen
            )
    }
}

// MARK: - List:

private extension ProductDetailsSectionView {
    private var list: some View {
        listContent
            .listStyle(.insetGrouped)
    }
    
    private var listContent: some View {
        List {
            screensContent
        }
    }
}

// MARK: - Screens:

private extension ProductDetailsSectionView {
    private var screensContent: some View {
        ForEach(
            screens,
            content: screen
        )
    }
    
    private func screen(_ screen: NT_ProductDetailsScreen) -> some View {
        ProductDetailsSectionRowView(
            screen: screen,
            viewAction: view
        )
    }
}

// MARK: - Screen:

private extension ProductDetailsSectionView {
    @ViewBuilder
    private func showScreen(_ screen: NT_ProductDetailsScreen) -> some View {
        switch screen {
        case .first: ProductDetailsOneView(product: product)
        case .second: ProductDetailsTwoView(product: product)
        case .third: ProductDetailsThreeView(product: product)
        case .fourth: ProductDetailsFourView(product: product)
        case .fifth: ProductDetailsFiveView(product: product)
        }
    }
}

// MARK: - Preview:

#Preview {
    ProductDetailsSectionView()
}
