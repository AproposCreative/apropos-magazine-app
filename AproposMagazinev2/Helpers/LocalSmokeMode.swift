import Foundation

/// The fixture UI and launch bypass cannot be activated in Release or on a device.
enum LocalSmokeMode {
    static var isEnabled: Bool {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("-AproposSmokeTesting")
        #else
        false
        #endif
    }
}
