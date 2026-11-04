import FirebaseAppCheck
import FirebaseCore
import DeviceCheck
import Foundation

/// Overrides Firebase's default DeviceCheck provider even while signup is off.
/// Only explicit limited-use requests may instantiate App Attest; ordinary
/// Firebase token requests and background refresh cannot start attestation.
final class ReaderAppAttestProviderFactory: NSObject, AppCheckProviderFactory {
    private let isEnabled: Bool

    init(isEnabled: Bool) { self.isEnabled = isEnabled }

    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        ReaderNewsletterAppCheckProvider { [isEnabled] in
            guard isEnabled, DCAppAttestService.shared.isSupported else { return nil }
            return AppAttestProvider(app: app)
        }
    }
}

/// The injected builder is lazy and can be tested without configuring Firebase.
final class ReaderNewsletterAppCheckProvider: NSObject, AppCheckProvider {
    private let makeProvider: () -> AppCheckProvider?
    private let lock = NSLock()
    private var provider: AppCheckProvider?

    init(makeProvider: @escaping () -> AppCheckProvider?) { self.makeProvider = makeProvider }

    private static var unavailable: NSError {
        NSError(domain: "AproposNewsletterAppCheck", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Newsletter attestation is unavailable."])
    }

    func getToken(completion: @escaping (AppCheckToken?, Error?) -> Void) {
        // This integration does not enable App Check for other Firebase APIs.
        completion(nil, Self.unavailable)
    }

    func getLimitedUseToken(completion: @escaping (AppCheckToken?, Error?) -> Void) {
        lock.lock()
        if provider == nil { provider = makeProvider() }
        let current = provider
        lock.unlock()
        guard let limitedUse = current?.getLimitedUseToken else {
            completion(nil, Self.unavailable)
            return
        }
        limitedUse(completion)
    }
}
