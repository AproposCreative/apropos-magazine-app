//
//  DataVisualizationThreeCharts+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension DataVisualizationThreeChartsView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !incomeCategories.isEmpty
        || !unpaidInvoices.isEmpty
        || !investments.isEmpty
    }
    
    /// An array of the bars to display in the chart for the income categories:
    var incomeCategoriesBars: [NT_ChartBar] {
        incomeCategories.map {
            .init(
                id: $0.id,
                title: $0.title,
                valueTitle: $0.title,
                value: $0.amount,
                color: $0.color,
                gradientStart: $0.gradientStart,
                gradientEnd: $0.gradientEnd
            )
        }
    }
    
    /// An array of the sectors to display in the chart for the unpaid invoices:
    var unpaidInvoicesSectors: [NT_ChartSector] {
        unpaidInvoices.map {
            .init(
                id: $0.id,
                valueTitle: $0.category.title,
                value: $0.amount,
                color: $0.category.color,
                gradientStart: $0.category.gradientStart,
                gradientEnd: $0.category.gradientEnd
            )
        }
    }
    
    /// An array of the lines to display in the chart for the investments:
    var investmentsLines: [NT_ChartLine] {
        investments.map {
            .init(
                id: $0.id,
                title: $0.title,
                color: $0.color,
                gradientStart: $0.gradientStart,
                gradientEnd: $0.gradientEnd,
                values: $0.values.map {
                    .init(
                        id: $0.id,
                        value: $0.value,
                        date: $0.date
                    )
                }
            )
        }
    }
}
