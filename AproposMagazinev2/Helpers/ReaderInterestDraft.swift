import Foundation

/// Memory-only edits owned by one accepted preferences generation. The caller
/// must reject stale account snapshots before adopting them; this stores no
/// identity or write authority and performs no persistence.
struct ReaderInterestDraft {
    private(set) var generation: UUID?
    private(set) var loadVersion: UUID?
    private(set) var selected = Set<String>()
    private var baseline = Set<String>()
    private var added = Set<String>()
    private var removed = Set<String>()

    var isDirty: Bool { selected != baseline }

    mutating func adopt(generation incomingGeneration: UUID, loadVersion incomingVersion: UUID?,
                        loaded: Bool, interestTopicIDs: [String]) {
        if generation != incomingGeneration {
            generation = incomingGeneration
            loadVersion = nil
            baseline = []
            selected = []
            added = []
            removed = []
        }
        // A waiting/error snapshot does not replace an already edited draft.
        guard loaded, let incomingVersion else { return }
        let server = normalized(interestTopicIDs)
        guard loadVersion != incomingVersion || baseline != server else { return }

        // A server match acknowledges only the matching explicit user edits.
        // A server topic omitted by the display limit was never a user removal.
        added.subtract(server)
        removed.formIntersection(server)
        let remainingServer = server.subtracting(removed)
        // Preserve every explicit local addition. If concurrent server additions
        // exceed the 20-topic limit, retain existing selected server topics next,
        // then fill spare places deterministically. No visible local selection
        // is discarded solely to make room for a newly arriving server topic.
        let retained = remainingServer.intersection(selected)
        let priority = added.sorted() + retained.subtracting(added).sorted()
        let extra = remainingServer.subtracting(added).subtracting(retained).sorted()
        selected = Set((priority + extra).prefix(20))
        baseline = server
        loadVersion = incomingVersion
    }

    mutating func toggle(_ id: String) {
        guard loadVersion != nil, !id.isEmpty else { return }
        if selected.contains(id) {
            selected.remove(id)
            added.remove(id)
            if baseline.contains(id) { removed.insert(id) }
        } else if selected.count < 20 {
            selected.insert(id)
            removed.remove(id)
            if !baseline.contains(id) { added.insert(id) }
        }
    }

    /// Introduction suggestions are explicit replacement edits, not a server
    /// acknowledgement, and therefore remain relative to the same baseline.
    mutating func replaceSelection(with ids: Set<String>) {
        guard loadVersion != nil else { return }
        selected = normalized(Array(ids))
        added = selected.subtracting(baseline)
        removed = baseline.subtracting(selected)
    }

    private func normalized(_ ids: [String]) -> Set<String> {
        Set(Set(ids.filter { !$0.isEmpty }).sorted().prefix(20))
    }
}
