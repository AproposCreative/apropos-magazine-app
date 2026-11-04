import Foundation

/// Pure synchronous admission shared by the explicitly configured recovery
/// composition. Unknown startup begins closed. This value performs no callback,
/// I/O or SDK lookup, so it can safely be the last check before a legacy write.
/// Omitting this object preserves the existing production writer behavior.
@MainActor
final class ReaderLegacyWriteAdmission {
    private(set) var isAllowed: Bool

    init(isAllowed: Bool = false) { self.isAllowed = isAllowed }

    func setAllowed(_ value: Bool) { isAllowed = value }
}
