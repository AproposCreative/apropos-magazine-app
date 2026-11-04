import Foundation

/// Own-save publications do not replace an open form's device-local draft.
/// Only a new owner epoch or an accepted profile load adopts stored values.
@MainActor
struct UserProfileFormAdoption {
    private var generation: UUID?
    private var lastAcceptedLoadVersion: UUID?

    mutating func shouldAdopt(_ snapshot: UserProfileState.Snapshot, acceptedLoadVersion: UUID?) -> Bool {
        if generation != snapshot.generation {
            generation = snapshot.generation
            lastAcceptedLoadVersion = snapshot.loaded ? acceptedLoadVersion : nil
            return true
        }
        guard snapshot.loaded, let acceptedLoadVersion,
              acceptedLoadVersion != lastAcceptedLoadVersion else { return false }
        lastAcceptedLoadVersion = acceptedLoadVersion
        return true
    }
}
