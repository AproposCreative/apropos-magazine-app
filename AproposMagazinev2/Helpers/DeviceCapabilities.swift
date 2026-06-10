import UIKit

enum DeviceCapabilities {
    /// Dynamic Island hardware (iPhone 14 Pro and later Pro/flagship models).
    /// Live Activities are only started on these devices; other iPhones still show
    /// lock-screen Live Activities, which we intentionally skip.
    static var hasDynamicIsland: Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }

        let machine = machineIdentifier
        let dynamicIslandModels: Set<String> = [
            "iPhone15,2", "iPhone15,3", // iPhone 14 Pro / Pro Max
            "iPhone16,1", "iPhone16,2", // iPhone 15 Pro / Pro Max
            "iPhone17,1", "iPhone17,2", // iPhone 16 Pro / Pro Max
            "iPhone17,3", "iPhone17,4", // iPhone 16 / 16 Plus
            "iPhone18,1", "iPhone18,2", // iPhone 17 Pro / Pro Max (anticipated)
            "iPhone18,3", "iPhone18,4", // iPhone 17 / 17 Air (anticipated)
        ]
        return dynamicIslandModels.contains(machine)
    }

    private static var machineIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}
