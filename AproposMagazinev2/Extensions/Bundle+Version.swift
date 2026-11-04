import Foundation

extension Bundle {
    var shortVersionString: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var buildVersionString: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}
