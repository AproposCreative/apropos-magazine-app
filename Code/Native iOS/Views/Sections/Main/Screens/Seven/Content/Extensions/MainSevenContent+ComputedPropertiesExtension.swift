//
//  MainSevenContent+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension MainSevenContentView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not an array of the products, as well as an array of the categories to display are both empty:
    var isEmpty: Bool {
        searchProducts.isEmpty && searchCategories.isEmpty
    }
    
    /// An array of the products that are filtered by the search text that is inputed by the user:
    var searchProducts: [NT_Product] {
        products.filter {
            isSearchTextEmpty
                ? true
                : $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    /// An array of the categories that are filtered by the search text that is inputed by the user:
    var searchCategories: [NT_ProductsCategory] {
        categories.filter {
            isSearchTextEmpty
                ? true
                : $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    /// Font of the buttons that are placed in the toolbar:
    var toolbarFont: Font {
        .body
    }
    
    /// Symbol variant of the icons of the buttons that are placed in the toolbar:
    var toolbarIconSymbolVariant: SymbolVariants {
        .none
    }
    
    /// Style of the buttons that are placed in the toolbar:
    var toolbarStyle: NT_LabelStyle {
        .iconOnly
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the text to search the products and the categories by that is inputed the user is empty:
    private var isSearchTextEmpty: Bool {
        searchText.isEmpty
    }
}
