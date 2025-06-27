//
//  MainNineDrives+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension MainNineDrivesView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given drive:
    func title(_ drive: NT_Drive) -> String {
        drive.title
    }
    
    /// Returns the count of the files that are part of the given drive as a string:
    func filesCount(_ drive: NT_Drive) -> String {
        "\(drive.filesCount) files"
    }
    
    /// Returns the capacity of the given drive as a string:
    func capacityString(_ drive: NT_Drive) -> String {
        capacity(drive).formatted(.byteCount(style: .file))
    }
    
    /// Returns the used capacity of the given drive as a string:
    func usedCapacityString(_ drive: NT_Drive) -> String {
        usedCapacity(drive).formatted(.byteCount(style: .file))
    }
    
    /// Returns the color of the given drive:
    func color(_ drive: NT_Drive) -> Color {
        drive.color
    }
    
    /// Returns the starting color of the gradient of the given drive:
    func gradientStart(_ drive: NT_Drive) -> Color {
        drive.gradientStart
    }
    
    /// Returns the ending color of the gradient of the given drive:
    func gradientEnd(_ drive: NT_Drive) -> Color {
        drive.gradientEnd
    }
    
    /// Returns the value of the capacity of the given drive:
    func capacityValue(_ drive: NT_Drive) -> Double {
        Double(capacity(drive))
    }
    
    /// Returns the value of the used capacity of the given drive:
    func usedCapacityValue(_ drive: NT_Drive) -> Double {
        Double(usedCapacity(drive))
    }
    
    // MARK: - Private functions:
    
    /// Returns the capacity of the given drive:
    private func capacity(_ drive: NT_Drive) -> Int64 {
        drive.capacity
    }
    
    /// Returns the used capacity of the given drive:
    private func usedCapacity(_ drive: NT_Drive) -> Int64 {
        drive.usedCapacity
    }
}
