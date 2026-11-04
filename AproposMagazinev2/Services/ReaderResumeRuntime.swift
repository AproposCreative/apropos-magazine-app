import Foundation

enum ReaderResumeRuntime {
    static let storageKey = "reader.resume.v1"
    static let applicationStore = ReaderResumeStore(storage: .init(
        read: {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: storageKey) == nil || defaults.data(forKey: storageKey) != nil else {
                throw ReaderResumeRecord.Failure.invalid
            }
            return defaults.data(forKey: storageKey)
        }, write: { UserDefaults.standard.set($0, forKey: storageKey) }))

    @MainActor static func makeController() -> ReaderResumeController {
        // Constructing the store performs no I/O. Tests/fixtures explicitly
        // inject their own memory store and never use production defaults.
        let disabled = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || LocalSmokeMode.isEnabled
        return ReaderResumeController(store: applicationStore, disabled: disabled,
            legacyAdmission: disabled ? nil : ReaderTransitionRecovery.application.admission)
    }
}
