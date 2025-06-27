//
//  NT_LineChartTotalValueType.swift
//  Native
//

import Foundation

enum NT_LineChartTotalValueType {
    
    // MARK: - Cases:
    
    /// If the option is set to all values, the total value of the line chart will add all of the values of each of the lines of the chart when calculating the total value to display:
    case allValues
    
    /// If the option is set to first value, the total value of the line chart will only add the first values of each of the lines of the chart when calculating the total value to display:
    case firstValue
    
    /// If the option is set to last value, the total value of the line chart will only add the last values of each of the lines of the chart when calculating the total value to display:
    case lastValue
    
    /// If the option is set to smallest value, the total value of the line chart will only add the smallest values of each of the lines of the chart when calculating the total value to display:
    case smallestValue
    
    /// If the option is set to largest value, the total value of the line chart will only add the largest values of each of the lines of the chart when calculating the total value to display:
    case largestValue
}
