import Foundation
import GoogleSignIn

/// Shared by delegate and SwiftUI scene, inert until an accepted entry invokes
/// its normal runtime. The fixture/test default can never initialize a service.
@MainActor
enum IncomingLinkEntryRuntime {
    static let entry = IncomingLinkEntry(
        disabled: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || LocalSmokeMode.isEnabled,
        handleGoogle: { GIDSignIn.sharedInstance.handle($0) },
        accept: { IncomingLinkRuntime.shared.accept($0) }
    )
}
