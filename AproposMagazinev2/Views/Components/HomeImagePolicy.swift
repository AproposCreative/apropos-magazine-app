import SwiftUI

enum HomeImagePolicy: Equatable {
    case remote
    case placeholder

    var allowsRemoteImages: Bool { self == .remote }
}

private struct HomeImagePolicyKey: EnvironmentKey {
    static let defaultValue: HomeImagePolicy = .remote
}

/// A local presentation override, never a write to the system accessibility
/// preference. Production defaults to the reader's actual OS preference.
private struct HomeReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var homeImagePolicy: HomeImagePolicy {
        get { self[HomeImagePolicyKey.self] }
        set { self[HomeImagePolicyKey.self] = newValue }
    }

    var homeReduceMotionOverride: Bool {
        get { self[HomeReduceMotionOverrideKey.self] }
        set { self[HomeReduceMotionOverrideKey.self] = newValue }
    }
}
