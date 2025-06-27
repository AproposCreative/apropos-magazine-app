//
//  DataVisualizationOneOverview+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension DataVisualizationOneOverviewView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given overview item:
    func title(_ overviewItem: NT_Overview) -> String {
        overviewItem.title
    }
    
    /// Returns the description of the given overview item:
    func description(_ overviewItem: NT_Overview) -> String {
        overviewItem.description
    }
    
    /// Returns the value of the given overview item as a string that is based on its type:
    func value(_ overviewItem: NT_Overview) -> String {
        switch overviewItem.type {
        case .amount: value(overviewItem).formatted(.currency(code: "USD").notation(.compactName))
        case .percentage: value(overviewItem).formatted(.percent)
        }
    }
    
    /// Returns the color of the given overview item:
    func color(_ overviewItem: NT_Overview) -> Color {
        overviewItem.color
    }
    
    /// Returns the starting color of the gradient of the given overview item:
    func gradientStart(_ overviewItem: NT_Overview) -> Color {
        overviewItem.gradientStart
    }
    
    /// Returns the ending color of the gradient of the given overview item:
    func gradientEnd(_ overviewItem: NT_Overview) -> Color {
        overviewItem.gradientEnd
    }
    
    /// Returns the icon of the given overview item:
    func icon(_ overviewItem: NT_Overview) -> String {
        overviewItem.icon
    }
    
    // MARK: - Private functions:
    
    /// Returns the value of the given overview item:
    private func value(_ overviewItem: NT_Overview) -> Double {
        overviewItem.value
    }
}
