//
//  NT_Product.swift
//  Native
//

import Foundation

struct NT_Product {
    
    // MARK: - Properties:
    
    /// Identifier of the product:
    let id: String
    
    /// Title of the product:
    let title: String
    
    /// Blurb of the product:
    let blurb: String
    
    /// Shorter description of the product that is displayed on the product card on the main screen:
    let shortDescription: String
    
    /// Longer description of the product that is displayed on details screen of the product:
    let longDescription: String
    
    /// Price of the product:
    let price: Double
    
    /// Large thumbnail image of the product:
    let largeThumbnailImage: String
    
    /// Small thumbnail image of the product:
    let smallThumbnailImage: String
    
    /// An array of the additional images of the product:
    let additionalImages: [String]
    
    /// An array of the key features of the product:
    let keyFeatures: [NT_ProductKeyFeature]
    
    /// An array of the reviews that the product has:
    let reviews: [NT_ProductReview]
    
    /// An array of the FAQ items of the product:
    let faqItems: [NT_ProductFAQ]
    
    /// An array of the storage options of the product:
    let storages: [NT_ProductStorage]
    
    /// An array of the configuration options of the product:
    let configurations: [NT_ProductConfiguration]
    
    /// An array of the colors of the product:
    let colors: [NT_Color]
    
    /// An array of the identifiers of the products that are similar to the product:
    let similarProducts: [String]
    
    init(
        id: String,
        title: String,
        blurb: String,
        shortDescription: String,
        longDescription: String,
        price: Double,
        largeThumbnailImage: String,
        smallThumbnailImage: String,
        additionalImages: [String],
        keyFeatures: [NT_ProductKeyFeature],
        reviews: [NT_ProductReview],
        faqItems: [NT_ProductFAQ],
        storages: [NT_ProductStorage],
        configurations: [NT_ProductConfiguration],
        colors: [NT_Color],
        similarProducts: [String]
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.blurb = blurb
        self.shortDescription = shortDescription
        self.longDescription = longDescription
        self.price = price
        self.largeThumbnailImage = largeThumbnailImage
        self.smallThumbnailImage = smallThumbnailImage
        self.additionalImages = additionalImages
        self.keyFeatures = keyFeatures
        self.reviews = reviews
        self.faqItems = faqItems
        self.storages = storages
        self.configurations = configurations
        self.colors = colors
        self.similarProducts = similarProducts
    }
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the product has the short description:
    var doesHaveShortDescription: Bool {
        !shortDescription.isEmpty
    }
}

// MARK: - Identifiable:

extension NT_Product: Identifiable {  }

// MARK: - Equatable:

extension NT_Product: Equatable {  }

// MARK: - Hashable:

extension NT_Product: Hashable {  }

// MARK: - Example:

extension NT_Product {
    
    // MARK: - Computed properties:
    
    /// An array of the example products:
    static var example: [NT_Product] {
        [
            .init(
                id: "Item.1",
                title: "Powerful Laptop 2024",
                blurb: "Supercharge your workflow",
                shortDescription: "This is one of the best laptops you will ever come across. It offers everything you might need and a lot more.",
                longDescription: "This is one of the best laptops you will ever come across. It offers everything you might need and a lot more for you to supercharge your daily workflow and get more work done in just a matter of time. All thanks to its outstanding performance and wonderful features that make this machine one of the best in its class.",
                price: 499.0,
                largeThumbnailImage: Images.productDetails1,
                smallThumbnailImage: Images.productDetails2,
                additionalImages: [
                    Images.productDetails2,
                    Images.productDetails4,
                    Images.productDetails6
                ],
                keyFeatures: NT_ProductKeyFeature.example,
                reviews: NT_ProductReview.example,
                faqItems: NT_ProductFAQ.example,
                storages: NT_ProductStorage.example,
                configurations: NT_ProductConfiguration.example,
                colors: NT_Color.example,
                similarProducts: [
                    "Item.2",
                    "Item.3",
                    "Item.4"
                ]
            ),
            .init(
                id: "Item.2",
                title: "Laptop for Your Creative Projects",
                blurb: "Unleash your creativity",
                shortDescription: "Featuring a sleek, lightweight design, this laptop is perfect for on-the-go creativity, making it easy to collaborate with others.",
                longDescription: "This is one of the best laptops you will ever come across. It offers everything you might need and a lot more for you to supercharge your daily workflow and get more work done in just a matter of time. All thanks to its outstanding performance and wonderful features that make this machine one of the best in its class.",
                price: 379.0,
                largeThumbnailImage: Images.productDetails3,
                smallThumbnailImage: Images.productDetails4,
                additionalImages: [
                    Images.productDetails4,
                    Images.productDetails6,
                    Images.productDetails8
                ],
                keyFeatures: NT_ProductKeyFeature.example,
                reviews: NT_ProductReview.example,
                faqItems: NT_ProductFAQ.example,
                storages: NT_ProductStorage.example,
                configurations: NT_ProductConfiguration.example,
                colors: NT_Color.example,
                similarProducts: [
                    "Item.3",
                    "Item.4",
                    "Item.5"
                ]
            ),
            .init(
                id: "Item.3",
                title: "Amazing Laptop for All Your Needs",
                blurb: "Streamline your success",
                shortDescription: "Streamline your success with a laptop that empowers you to achieve your goals faster and more effectively than ever before.",
                longDescription: "This is one of the best laptops you will ever come across. It offers everything you might need and a lot more for you to supercharge your daily workflow and get more work done in just a matter of time. All thanks to its outstanding performance and wonderful features that make this machine one of the best in its class.",
                price: 439.0,
                largeThumbnailImage: Images.productDetails5,
                smallThumbnailImage: Images.productDetails6,
                additionalImages: [
                    Images.productDetails6,
                    Images.productDetails8,
                    Images.productDetails10
                ],
                keyFeatures: NT_ProductKeyFeature.example,
                reviews: NT_ProductReview.example,
                faqItems: NT_ProductFAQ.example,
                storages: NT_ProductStorage.example,
                configurations: NT_ProductConfiguration.example,
                colors: NT_Color.example,
                similarProducts: [
                    "Item.4",
                    "Item.5",
                    "Item.6"
                ]
            ),
            .init(
                id: "Item.4",
                title: "Lightweight and Powerful Laptop",
                blurb: "Elevate the performance",
                shortDescription: "Elevate the performance and level up your work with a laptop engineered for success.",
                longDescription: "This is one of the best laptops you will ever come across. It offers everything you might need and a lot more for you to supercharge your daily workflow and get more work done in just a matter of time. All thanks to its outstanding performance and wonderful features that make this machine one of the best in its class.",
                price: 629.0,
                largeThumbnailImage: Images.productDetails7,
                smallThumbnailImage: Images.productDetails8,
                additionalImages: [
                    Images.productDetails8,
                    Images.productDetails10,
                    Images.productDetails12
                ],
                keyFeatures: NT_ProductKeyFeature.example,
                reviews: NT_ProductReview.example,
                faqItems: NT_ProductFAQ.example,
                storages: NT_ProductStorage.example,
                configurations: NT_ProductConfiguration.example,
                colors: NT_Color.example,
                similarProducts: [
                    "Item.5",
                    "Item.6",
                    "Item.1"
                ]
            ),
            .init(
                id: "Item.5",
                title: "Perfect Work Laptop",
                blurb: "Transform ideas into action",
                shortDescription: "With this laptop, you can easily get all of your work done in just a matter of time. All thanks to its amazing performance.",
                longDescription: "This is one of the best laptops you will ever come across. It offers everything you might need and a lot more for you to supercharge your daily workflow and get more work done in just a matter of time. All thanks to its outstanding performance and wonderful features that make this machine one of the best in its class.",
                price: 999.0,
                largeThumbnailImage: Images.productDetails9,
                smallThumbnailImage: Images.productDetails10,
                additionalImages: [
                    Images.productDetails12,
                    Images.productDetails10,
                    Images.productDetails8
                ],
                keyFeatures: NT_ProductKeyFeature.example,
                reviews: NT_ProductReview.example,
                faqItems: NT_ProductFAQ.example,
                storages: NT_ProductStorage.example,
                configurations: NT_ProductConfiguration.example,
                colors: NT_Color.example,
                similarProducts: [
                    "Item.6",
                    "Item.1",
                    "Item.2"
                ]
            ),
            .init(
                id: "Item.6",
                title: "Laptop for Your Studies",
                blurb: "All you need to study",
                shortDescription: "Get ready to excel in your studies with a laptop that truly has all you need to succeed.",
                longDescription: "This is one of the best laptops you will ever come across. It offers everything you might need and a lot more for you to supercharge your daily workflow and get more work done in just a matter of time. All thanks to its outstanding performance and wonderful features that make this machine one of the best in its class.",
                price: 289.0,
                largeThumbnailImage: Images.productDetails11,
                smallThumbnailImage: Images.productDetails12,
                additionalImages: [
                    Images.productDetails8,
                    Images.productDetails6,
                    Images.productDetails4
                ],
                keyFeatures: NT_ProductKeyFeature.example,
                reviews: NT_ProductReview.example,
                faqItems: NT_ProductFAQ.example,
                storages: NT_ProductStorage.example,
                configurations: NT_ProductConfiguration.example,
                colors: NT_Color.example,
                similarProducts: [
                    "Item.1",
                    "Item.2",
                    "Item.3"
                ]
            )
        ]
    }
}
