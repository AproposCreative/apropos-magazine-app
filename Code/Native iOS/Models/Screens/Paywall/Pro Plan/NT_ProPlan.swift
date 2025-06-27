//
//  NT_ProPlan.swift
//  Native
//

import Foundation

struct NT_ProPlan {
    
    // MARK: - Properties:
    
    /// Identifier of the pro plan:
    let id: String
    
    /// Title of the pro plan:
    let title: String
    
    /// Price and the duration of the pro plan as a string:
    let price: String
    
    /// Price of the pro plan as a string:
    let priceOnly: String
    
    init(
        id: String,
        title: String,
        price: String,
        priceOnly: String
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.price = price
        self.priceOnly = priceOnly
    }
    
    // MARK: - Computed properties:
    
    /// Type of the pro plan (Please add your own implantation to determine which type of the plan it actually is):
    var type: NT_ProPlanType {
        if id == ProPlanIdentifiers.monthly {
            return .monthly
        } else if id == ProPlanIdentifiers.yearly {
            return .yearly
        } else if id == ProPlanIdentifiers.lifetime {
            return .lifetime
        } else {
            return .none
        }
    }
}

// MARK: - Identifiable:

extension NT_ProPlan: Identifiable {  }

// MARK: - Equatable:

extension NT_ProPlan: Equatable {  }

// MARK: - Hashable:

extension NT_ProPlan: Hashable {  }

// MARK: - Example:

extension NT_ProPlan {
    
    // MARK: - Computed properties:
    
    /// An array of the example pro plans:
    static var examplePlans: [NT_ProPlan] {
        [
            .init(
                id: ProPlanIdentifiers.monthly,
                title: "Monthly",
                price: "$2.99 / Month",
                priceOnly: "$2.99"
            ),
            .init(
                id: ProPlanIdentifiers.yearly,
                title: "Yearly",
                price: "$9.99 / Year",
                priceOnly: "$9.99"
            ),
            .init(
                id: ProPlanIdentifiers.lifetime,
                title: "Lifetime",
                price: "$29.99 / Lifetime",
                priceOnly: "$29.99"
            )
        ]
    }
}
