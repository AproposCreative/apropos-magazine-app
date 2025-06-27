//
//  DataVisualizationTwoUsage+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension DataVisualizationTwoUsageView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given usage item:
    func title(_ usageItem: NT_Usage) -> String {
        usageItem.title
    }
    
    /// Returns the total value of the given usage item as a string:
    func totalValueString(_ usageItem: NT_Usage) -> String {
        switch type(usageItem) {
        case .storage(let total, _): return total.formatted(.byteCount(style: .file))
        case .value(let total, _): return total.formatted(.number)
        }
    }
    
    /// Returns the used value of the given usage item as a string:
    func usedValueString(_ usageItem: NT_Usage) -> String {
        switch type(usageItem) {
        case .storage(_, let used): return used.formatted(.byteCount(style: .file))
        case .value(_, let used): return used.formatted(.number)
        }
    }
    
    /// Returns the color of the given usage item:
    func color(_ usageItem: NT_Usage) -> Color {
        usageItem.color
    }
    
    /// Returns the starting color of the gradient of the given usage item:
    func gradientStart(_ usageItem: NT_Usage) -> Color {
        usageItem.gradientStart
    }
    
    /// Returns the ending color of the gradient of the given usage item:
    func gradientEnd(_ usageItem: NT_Usage) -> Color {
        usageItem.gradientEnd
    }
    
    /// Returns the icon of the given usage item:
    func icon(_ usageItem: NT_Usage) -> String {
        usageItem.icon
    }
    
    /// Returns the total value of the given usage item:
    func totalValue(_ usageItem: NT_Usage) -> Double {
        switch type(usageItem) {
        case .storage(let total, _): return .init(total)
        case .value(let total, _): return total
        }
    }
    
    /// Returns the used value of the given usage item:
    func usedValue(_ usageItem: NT_Usage) -> Double {
        switch type(usageItem) {
        case .storage(_, let used): return .init(used)
        case .value(_, let used): return used
        }
    }
    
    // MARK: - Private functions:
    
    /// Returns the type of the given usage item:
    private func type(_ usageItem: NT_Usage) -> NT_UsageType {
        usageItem.type
    }
}
