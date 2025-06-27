//
//  MainSevenContentView.swift
//  Native
//

import SwiftUI

struct MainSevenContentView: View {
    
    // MARK: - Properties:
    
    /// An array of the products to display:
    @State var products: [NT_Product] = []
    
    /// An array of the categories to display:
    @State var categories: [NT_ProductsCategory] = []
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    /// Text to search the products and the categories by that is inputed by the user:
    @State var searchText: String = ""
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        scroll
            .background(Color(.systemGroupedBackground))
            .localizedNavigationTitle(title: "Explore")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer
            )
            .toolbarButton(
                title: "Messages",
                icon: Icons.bubble,
                iconSymbolVariant: toolbarIconSymbolVariant,
                font: toolbarFont,
                style: toolbarStyle,
                placement: .cancellationAction,
                action: showMessages
            )
            .toolbarButton(
                title: "Cart",
                icon: Icons.cart,
                iconSymbolVariant: toolbarIconSymbolVariant,
                font: toolbarFont,
                style: toolbarStyle,
                action: showCart
            )
            .navigationDestination(
                for: NT_ProductsCategory.self,
                destination: category
            )
            .animation(
                .default,
                value: searchProducts
            )
            .animation(
                .default,
                value: searchCategories
            )
            .animation(
                .default,
                value: isFetching
            )
            .task {
                await fetchData()
            }
            .navigationStack()
    }
}

// MARK: - Scroll:

private extension MainSevenContentView {
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
    
    @ViewBuilder
    private var scrollItem: some View {
        if isFetching {
            loading
        } else if isEmpty {
            nothingHere
        } else {
            bannerProductsCategories
        }
    }
}

// MARK: - Empty states:

private extension MainSevenContentView {
    private var loading: some View {
        loadingContent
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
            .containerRelativeFrame(
                .vertical,
                alignment: .center
            )
    }
    
    private var loadingContent: some View {
        LoadingView(
            isShowing: true,
            color: .secondary,
            scale: 1.5
        )
    }
    
    private var nothingHere: some View {
        nothingHereContent
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
            .containerRelativeFrame(
                .vertical,
                alignment: .center
            )
    }
    
    private var nothingHereContent: some View {
        EmptyStateView(
            title: "Nothing Here",
            subtitle: "We don't have anything to display here."
        )
    }
}

// MARK: - Banner, products, and categories:

private extension MainSevenContentView {
    private var bannerProductsCategories: some View {
        VStack(
            alignment: .leading,
            spacing: 32
        ) {
            bannerProductsCategoriesContent
        }
    }
    
    @ViewBuilder
    private var bannerProductsCategoriesContent: some View {
        MainSevenBannerView()
        MainSevenProductsView(products: products)
        MainSevenCategoriesView(categories: categories)
    }
}

// MARK: - Product and category:

private extension MainSevenContentView {
    private func category(_ category: NT_ProductsCategory) -> some View {
        PlaceholderView(title: title(category))
    }
}

// MARK: - Preview:

#Preview {
    MainSevenContentView()
}
