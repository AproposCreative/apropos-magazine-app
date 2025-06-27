//
//  NT_ProductCategory.swift
//  Native
//

import SwiftUI

struct NT_ProductsCategory {
    
    // MARK: - Properties:
    
    /// Identifier of the category:
    let id: String
    
    /// Title of the category:
    let title: String
    
    /// Color of the category:
    let color: Color
    
    /// Starting color of the gradient of the category:
    let gradientStart: Color
    
    /// Ending color of the gradient of the category:
    let gradientEnd: Color
    
    /// Icon of the category:
    let icon: String
    
    /// An array of the products that are part of the category:
    let products: [NT_Product]
    
    init(
        id: String,
        title: String,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color,
        icon: String,
        products: [NT_Product]
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.icon = icon
        self.products = products
    }
    
    // MARK: - Computed properties:
    
    /// Count of the products that are part of the category:
    var productsCount: Int {
        products.count
    }
}

// MARK: - Identifiable:

extension NT_ProductsCategory: Identifiable {  }

// MARK: - Equatable:

extension NT_ProductsCategory: Equatable {  }

// MARK: - Hashable:

extension NT_ProductsCategory: Hashable {  }

// MARK: - Example:

extension NT_ProductsCategory {
    
    // MARK: - Computed properties:
    
    /// An array of the example categories:
    static var example: [NT_ProductsCategory] {
        [
            .init(
                id: "Item.1",
                title: "New",
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd,
                icon: Icons.sparkles,
                products: NT_Product.example.filter {
                    $0.id == "Item.1"
                    || $0.id == "Item.2"
                }
            ),
            .init(
                id: "Item.2",
                title: "Work",
                color: .orange,
                gradientStart: .orangeGradientStart,
                gradientEnd: .orangeGradientEnd,
                icon: Icons.briefcase,
                products: NT_Product.example.filter {
                    $0.id == "Item.2"
                    || $0.id == "Item.3"
                    || $0.id == "Item.4"
                }
            ),
            .init(
                id: "Item.3",
                title: "Education",
                color: .purple,
                gradientStart: .purpleGradientStart,
                gradientEnd: .purpleGradientEnd,
                icon: Icons.graduationcap,
                products: NT_Product.example.filter {
                    $0.id == "Item.3"
                    || $0.id == "Item.6"
                }
            ),
            .init(
                id: "Item.4",
                title: "Creativity",
                color: .pink,
                gradientStart: .pinkGradientStart,
                gradientEnd: .pinkGradientEnd,
                icon: Icons.paintbrush,
                products: NT_Product.example.filter {
                    $0.id == "Item.1"
                    || $0.id == "Item.2"
                }
            ),
            .init(
                id: "Item.5",
                title: "Gaming",
                color: .green,
                gradientStart: .greenGradientStart,
                gradientEnd: .greenGradientEnd,
                icon: Icons.gamecontroller,
                products: NT_Product.example.filter {
                    $0.id == "Item.1"
                    || $0.id == "Item.4"
                    || $0.id == "Item.5"
                }
            ),
            .init(
                id: "Item.6",
                title: "Entertainment",
                color: .indigo,
                gradientStart: .indigoGradientStart,
                gradientEnd: .indigoGradientEnd,
                icon: Icons.popcorn,
                products: NT_Product.example.filter {
                    $0.id == "Item.1"
                    || $0.id == "Item.4"
                }
            )
        ]
    }
}
