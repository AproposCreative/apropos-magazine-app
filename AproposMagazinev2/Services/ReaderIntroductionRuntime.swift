import Foundation

/// Constructing these adapters performs no I/O. Normal startup explicitly binds
/// the canonical context and reads the two independent, device-local records.
@MainActor
enum ReaderIntroductionRuntime {
    static let introduction = ReaderIntroductionModel(storage: storage("reader.introduction.v1", cleanupKey: "reader.introduction.cleanup.v1"),
        recovery: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || LocalSmokeMode.isEnabled
            ? nil : ReaderTransitionRecovery.application)
    static let guestInterests = GuestReaderInterestsModel(storage: storage("reader.guestInterests.v1"))

    /// The same model owns normal writing and explicit recovery cleanup.
    /// Merely resolving it performs no source, sidecar or guest-storage I/O.
    static func localCleanupModel() -> ReaderIntroductionModel { introduction }

    private static func storage(_ key: String, cleanupKey: String? = nil) -> ReaderIntroductionStorage {
        let cleanup: ReaderIntroductionStorage.Cleanup? = cleanupKey.map { cleanupKey in
            .init(read: {
                let defaults = UserDefaults.standard
                guard defaults.object(forKey: cleanupKey) == nil || defaults.data(forKey: cleanupKey) != nil else {
                    throw ReaderIntroductionLocalCleanupRecord.Failure.invalidRecord
                }
                return defaults.data(forKey: cleanupKey)
            }, write: { UserDefaults.standard.set($0, forKey: cleanupKey) })
        }
        return .init(read: {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: key) == nil || defaults.data(forKey: key) != nil else {
                throw ReaderIntroductionLocalCleanupRecord.Failure.invalidRecord
            }
            return defaults.data(forKey: key)
        }, write: { UserDefaults.standard.set($0, forKey: key) }, cleanup: cleanup)
    }
}
