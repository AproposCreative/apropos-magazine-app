import Foundation

/// Firebase's reauthentication callback can contain both a result and an error
/// (for example userMismatch). An error must win even when a value is present.
enum ReaderReauthenticationCallback {
    struct MissingResult: Error {}

    static func result<Value>(_ value: Value?, error: Error?) -> Result<Value, Error> {
        if let error { return .failure(error) }
        guard let value else { return .failure(MissingResult()) }
        return .success(value)
    }
}
