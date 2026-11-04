import CryptoKit
import Combine
import Foundation

/// Public bytes are reusable. Only a current favorite membership and its exact
/// accepted revision grant offline access or permit a media pin side effect.
@MainActor
final class FavoritesOfflineCoordinator {
    enum BodyState: Equatable { case checking, notDownloaded, pending, failed, available }
    enum AudioState: Equatable { case waitingForPublication, waiting, checking, downloading, available, failed, storageLimit, disabled }
    struct LibraryOfflineSummary: Equatable {
        let total: Int
        let ready: Int
        let textAvailable: Int
        let audioAvailable: Int
        let audioPending: Int
        let audioDisabled: Int
        let awaitingAudio: Int
        let failed: Int
        let storageLimited: Int
        let isLoaded: Bool
    }
    struct LibraryBodySummary: Equatable {
        let total: Int
        let available: Int
        let checking: Int
        let pending: Int
        let failed: Int
        let notDownloaded: Int
        let checkFailed: Int
        let isLoaded: Bool
    }
    struct LibraryMembershipIdentity: Equatable {
        let generation: UUID
        let members: [FavoritesModel.MembershipTicket]
        let isLoaded: Bool
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.generation == rhs.generation && lhs.isLoaded == rhs.isLoaded
                && lhs.members.count == rhs.members.count
                && zip(lhs.members, rhs.members).allSatisfy { pair in pair.0.identifiesSameMembership(as: pair.1) }
        }
    }
    struct LibraryRefreshHandle: Equatable {
        let id: UUID
        let generation: UUID
    }
    typealias FetchBody = @MainActor (String, @escaping @MainActor (Result<Article, Error>) -> Void) -> Void
    typealias Probe = @MainActor (String, @escaping @MainActor (Result<Bool, Error>) -> Void) -> Void
    struct AccessTicket: Equatable {
        let articleID: String
        let contentRevision: String
        let contentKey: String
        let pinKey: String
        let leaseID: UUID
        fileprivate let membership: FavoritesModel.MembershipTicket
    }
    struct Storage {
        let read: @MainActor (String) throws -> Article?
        let write: @MainActor (String, Article) throws -> Void
        let contains: @MainActor (String) throws -> Bool
        let probe: Probe
        let remove: @MainActor (String) throws -> Void
        init(read: @escaping @MainActor (String) throws -> Article?, write: @escaping @MainActor (String, Article) throws -> Void,
             contains: (@MainActor (String) throws -> Bool)? = nil, probe: Probe? = nil,
             remove: @escaping @MainActor (String) throws -> Void = { _ in }) {
            self.read = read; self.write = write; self.remove = remove
            let contains = contains ?? { try read($0) != nil }
            self.contains = contains
            // Existing in-memory adapters can complete synchronously. The live
            // adapter explicitly supplies its bounded background probe.
            self.probe = probe ?? { key, completion in completion(Result { try contains(key) }) }
        }
    }
    typealias Cancel = @MainActor () -> Void
    struct Effects {
        let cacheImages: @MainActor (Article, String) -> Void
        let audioAsset: @MainActor (Article) -> PodcastAudioAsset?
        let audioIsCached: @MainActor (PodcastAudioAsset) -> Bool
        let pinAudio: @MainActor (String, UUID, PodcastAudioAsset) -> Void
        let releaseAudio: @MainActor (String, UUID, PodcastAudioAsset) -> Void
        let scheduleRetry: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Cancel
        var audioState: (@MainActor (PodcastAudioAsset) -> AudioState)? = nil
        var audioProgress: (@MainActor (PodcastAudioAsset) -> Double?)? = nil
        var removeImages: @MainActor (String) -> Void = { _ in }
        var removeAudio: @MainActor (PodcastAudioAsset) -> Void = { _ in }
    }
    nonisolated static let maximumBodyBytes = 4 * 1024 * 1024
    private let model: FavoritesModel
    private let requiresAccount: Bool
    private var permitsAccountAccess: Bool {
        !requiresAccount || (model.context.namespace != nil && model.context.namespace != .guest)
    }
    private let storage: Storage
    private let permitsBody: @MainActor (Article) -> Bool
    private let effects: Effects
    private var access: [String: AccessTicket] = [:]
    private var pins: [String: (ticket: AccessTicket, asset: PodcastAudioAsset)] = [:]
    private struct AudioPinRequest: Hashable {
        let leaseID: UUID
        let asset: PodcastAudioAsset
    }
    private var audioPinRequests: Set<AudioPinRequest> = []
    private var retries: [UUID: (id: UUID, cancel: Cancel?)] = [:]
    private var synchronizing = false
    private var bodyCache: [(key: String, article: Article)] = []
    private let bodyChangeSubject = PassthroughSubject<Void, Never>()
    var bodyChanges: AnyPublisher<Void, Never> { bodyChangeSubject.eraseToAnyPublisher() }
    private var bodyStates: [UUID: BodyState] = [:]
    // A failed decoded read is stronger evidence than a matching size index.
    // Only a validated read or confirmed replacement save may clear it.
    private var invalidBodyReads: Set<UUID> = []
    private var bodyProbeFailures: Set<UUID> = []
    private var bodyOperations: [UUID: UUID] = [:]
    private var bodySaves: [UUID: UUID] = [:]
    // Revocation invalidates delivery, not an outstanding physical fetch. Slots
    // are freed only by its callback (or before the transport was started).
    private var bodyFetches: [UUID: AccessTicket] = [:]
    private var bodyChangeID = UUID()
    private let maximumBodyFetches = 4
    private enum BodyRequestResult { case accepted, rejected, waitingForCapacity }
    private struct LibraryBodyDownload {
        let id: UUID
        let tickets: [AccessTicket]
        let fetch: FetchBody
        var cursor = 0
        var waitingLeaseIDs: Set<UUID>
    }
    private var libraryBodyDownload: LibraryBodyDownload?
    private var libraryBodyDownloadID = UUID()
    private var pumpingLibraryBodyDownloads = false
    private struct BodyProbe { let id: UUID; let ticket: AccessTicket }
    private var bodyProbes: [UUID: AccessTicket] = [:]
    private var pendingBodyProbe: BodyProbe?
    private let maximumBodyProbes = 4
    private struct LibraryEntry {
        let membership: FavoritesModel.MembershipTicket
        let access: AccessTicket?
        let operation: UUID?
    }
    private struct LibraryRefresh {
        let handle: LibraryRefreshHandle
        let identity: LibraryMembershipIdentity
        var entries: [LibraryEntry]
        let force: Bool
        var pendingEntries: [String: LibraryEntry]
        var cursor = 0
    }
    private var libraryRefresh: LibraryRefresh?
    private var libraryEntryID = UUID()
    private var libraryProbeOwners: [UUID: UUID] = [:]
    private var pumpingBodyProbes = false

    init(model: FavoritesModel, requiresAccount: Bool = false, storage: Storage, permitsBody: @escaping @MainActor (Article) -> Bool, effects: Effects) {
        self.model = model
        self.requiresAccount = requiresAccount
        self.storage = storage
        self.permitsBody = permitsBody
        self.effects = effects
    }

    func captureAccess(articleID: String) -> AccessTicket? {
        guard permitsAccountAccess, let member = model.membershipTicket(articleID: articleID),
              let revision = member.contentRevision, !revision.isEmpty,
              permitsBody(member.article), model.isCurrent(member) else { return nil }
        if let existing = access[articleID], model.isCurrent(existing.membership),
           existing.membership.namespace == member.namespace, existing.membership.generation == member.generation,
           existing.contentRevision == revision { return existing }
        let key = Self.digest([articleID, revision])
        let ticket = AccessTicket(articleID: articleID, contentRevision: revision, contentKey: key,
            pinKey: "favorites-v1:" + Self.digest([member.namespace.recordBinding, articleID, revision]),
            leaseID: UUID(), membership: member)
        let previous = access.updateValue(ticket, forKey: articleID)
        if let previous { release(previous) }
        guard isCurrent(ticket) else { return nil }
        return ticket
    }

    func isCurrent(_ ticket: AccessTicket) -> Bool {
        guard permitsAccountAccess, access[ticket.articleID] == ticket, model.isCurrent(ticket.membership),
              ticket.membership.contentRevision == ticket.contentRevision, permitsBody(ticket.membership.article) else { return false }
        return permitsAccountAccess && access[ticket.articleID] == ticket && model.isCurrent(ticket.membership)
    }

    func body(articleID: String) -> Article? {
        guard let ticket = captureAccess(articleID: articleID) else { return nil }
        return body(ticket)
    }

    func body(_ ticket: AccessTicket) -> Article? {
        guard isCurrent(ticket) else { return nil }
        if let cached = bodyCache.first(where: { $0.key == ticket.contentKey }), matches(cached.article, ticket: ticket), isCurrent(ticket) { return cached.article }
        guard isCurrent(ticket) else { return nil }
        let operation = bodyOperations[ticket.leaseID]
        guard let value = try? storage.read(ticket.contentKey),
              matches(value, ticket: ticket), isCurrent(ticket) else {
            withdrawBodyStatus(ticket, operation: operation, invalidRead: true)
            return nil
        }
        guard bodyOperations[ticket.leaseID] == operation else { return nil }
        remember(value, key: ticket.contentKey)
        invalidBodyReads.remove(ticket.leaseID)
        bodyProbeFailures.remove(ticket.leaseID)
        if bodyStates[ticket.leaseID] != .pending, bodyStates[ticket.leaseID] != .failed,
           bodyStates[ticket.leaseID] != .available {
            let id = UUID(); bodyOperations[ticket.leaseID] = id
            bodyStates[ticket.leaseID] = .available; publishBodyChange()
            guard ownsBodyOperation(id, ticket: ticket) else { return nil }
        }
        return value
    }

    func hasBody(articleID: String, expectedRevision: String?) -> Bool {
        guard let ticket = captureAccess(articleID: articleID), expectedRevision.map({ $0 == ticket.contentRevision }) ?? true else { return false }
        let operation = bodyOperations[ticket.leaseID]
        let stored = (try? storage.contains(ticket.contentKey)) == true
        guard isCurrent(ticket), bodyOperations[ticket.leaseID] == operation else { return false }
        if !stored { withdrawBodyStatus(ticket, operation: operation) }
        return stored && !invalidBodyReads.contains(ticket.leaseID)
    }

    var currentAccessTickets: [AccessTicket] { model.snapshot.articles.compactMap { captureAccess(articleID: $0.id) } }

    var currentBodies: [Article] { model.snapshot.articles.compactMap { body(articleID: $0.id) } }

    /// Membership metadata only: neither disk access nor lease creation occurs
    /// while SwiftUI computes its lifecycle identity or renders a count.
    var libraryMembershipIdentity: LibraryMembershipIdentity {
        let snapshot = model.snapshot
        return LibraryMembershipIdentity(generation: snapshot.generation,
            members: snapshot.articles.compactMap { model.membershipTicket(articleID: $0.id) },
            isLoaded: model.canChangeSelection)
    }

    var libraryBodySummary: LibraryBodySummary {
        let snapshot = model.snapshot, change = bodyChangeID
        var available = 0, checking = 0, pending = 0, failed = 0, missing = 0, checkFailed = 0
        for article in snapshot.articles {
            let state: BodyState
            if article.bodyRevision?.isEmpty != false {
                state = .checking
            } else if let ticket = access[article.id], isCurrent(ticket) {
                let known = displayedBodyState(ticket)
                if known == .notDownloaded, bodyProbeFailures.contains(ticket.leaseID) {
                    checkFailed += 1; continue
                }
                // A queued forced check is unknown already, but a save/fetch
                // accepted since capture always outranks that old observation.
                if known != .pending && known != .failed && !invalidBodyReads.contains(ticket.leaseID),
                   let refresh = libraryRefresh, refresh.force,
                   let entry = refresh.pendingEntries[article.id],
                   entry.access == ticket, entry.operation == bodyOperations[ticket.leaseID] {
                    state = .checking
                } else { state = known }
            } else { state = .checking }
            switch state {
            case .available: available += 1
            case .checking: checking += 1
            case .pending: pending += 1
            case .failed: failed += 1
            case .notDownloaded: missing += 1
            }
        }
        guard model.snapshot.generation == snapshot.generation,
              model.snapshot.revision == snapshot.revision, bodyChangeID == change else {
            let latest = model.snapshot
            return LibraryBodySummary(total: latest.articles.count, available: 0,
                checking: latest.articles.count, pending: 0, failed: 0, notDownloaded: 0, checkFailed: 0,
                isLoaded: model.canChangeSelection)
        }
        return LibraryBodySummary(total: snapshot.articles.count, available: available,
            checking: checking, pending: pending, failed: failed, notDownloaded: missing, checkFailed: checkFailed,
            isLoaded: model.canChangeSelection)
    }

    /// One snapshot cursor shares the existing four physical probe slots. It
    /// never fills/overwrites the separate latest-detail waiting position.
    @discardableResult
    func prepareLibraryBodyStatus(force: Bool = false) -> LibraryRefreshHandle? {
        let entryID = UUID(); libraryEntryID = entryID
        let identity = libraryMembershipIdentity
        if let refresh = libraryRefresh, refresh.identity == identity,
           !force || refresh.cursor < refresh.entries.count || libraryProbeOwners.values.contains(refresh.handle.id) {
            return refresh.handle
        }
        if let old = libraryRefresh { retireLibraryBodyStatus(old.handle) }
        // Cancellation publication can reenter and install a newer request.
        guard libraryEntryID == entryID, libraryRefresh == nil, identity == libraryMembershipIdentity else { return nil }
        guard identity.isLoaded else { return nil }
        let handle = LibraryRefreshHandle(id: UUID(), generation: identity.generation)
        let entries = identity.members.map { member in
            let ticket = access[member.articleID]
            return LibraryEntry(membership: member, access: ticket, operation: ticket.flatMap { bodyOperations[$0.leaseID] })
        }
        guard libraryEntryID == entryID else { return nil }
        libraryRefresh = LibraryRefresh(handle: handle, identity: identity, entries: entries, force: force,
            pendingEntries: Dictionary(uniqueKeysWithValues: entries.map { ($0.membership.articleID, $0) }))
        publishBodyChange()
        guard libraryRefresh?.handle == handle else { return nil }
        pumpBodyProbe()
        return libraryRefresh?.handle == handle ? handle : nil
    }

    func cancelLibraryBodyStatus(_ handle: LibraryRefreshHandle) {
        guard libraryRefresh?.handle == handle else { return }
        libraryEntryID = UUID()
        retireLibraryBodyStatus(handle)
    }

    private func retireLibraryBodyStatus(_ handle: LibraryRefreshHandle) {
        guard libraryRefresh?.handle == handle else { return }
        libraryRefresh = nil
        var changed = false
        for (id, owner) in Array(libraryProbeOwners) where owner == handle.id {
            libraryProbeOwners.removeValue(forKey: id)
            guard let ticket = bodyProbes[id], bodyOperations[ticket.leaseID] == id else { continue }
            bodyOperations.removeValue(forKey: ticket.leaseID)
            if bodyStates[ticket.leaseID] == .checking {
                bodyStates.removeValue(forKey: ticket.leaseID); changed = true
            }
        }
        // Physical slots remain occupied until their original callback. A
        // detail that joined a library probe has removed its library ownership.
        if changed { publishBodyChange() }
    }

    /// Rendering reads memory only. A cold display remains unknown until an
    /// explicit appearance/activation probe completes; it never reads the index.
    func bodyState(ticket: AccessTicket) -> BodyState? {
        let change = bodyChangeID
        guard isCurrent(ticket), change == bodyChangeID else { return nil }
        return displayedBodyState(ticket)
    }

    private func displayedBodyState(_ ticket: AccessTicket) -> BodyState {
        let known = bodyStates[ticket.leaseID] ?? .checking
        if known != .available, libraryBodyDownload?.waitingLeaseIDs.contains(ticket.leaseID) == true {
            return .pending
        }
        return known
    }

    /// Called from lifecycle/action entry, never a display getter. Four actual
    /// probes and at most the latest waiting detail lease bound physical work.
    @discardableResult
    func prepareBodyStatus(ticket: AccessTicket, force: Bool = false) -> Bool {
        let change = bodyChangeID, operation = bodyOperations[ticket.leaseID]
        guard isCurrent(ticket), change == bodyChangeID, bodyOperations[ticket.leaseID] == operation,
              bodyStates[ticket.leaseID] != .pending, bodyStates[ticket.leaseID] != .failed,
              bodySaves[ticket.leaseID] == nil else { return false }
        if invalidBodyReads.contains(ticket.leaseID) { return true }
        // Appearance and foreground may arrive together. Even forced
        // revalidation joins an already current physical/queued observation.
        if let id = bodyOperations[ticket.leaseID], bodyProbes[id] == ticket || pendingBodyProbe?.id == id {
            libraryProbeOwners.removeValue(forKey: id)
            return true
        }
        if force {
            guard invalidateBodyStatus(ticket: ticket) else { return false }
        } else if let state = bodyStates[ticket.leaseID], state != .checking {
            return true
        }
        let preparedChange = bodyChangeID, preparedOperation = bodyOperations[ticket.leaseID]
        guard isCurrent(ticket), preparedChange == bodyChangeID, bodyOperations[ticket.leaseID] == preparedOperation,
              bodyStates[ticket.leaseID] != .pending, bodyStates[ticket.leaseID] != .failed,
              bodySaves[ticket.leaseID] == nil else { return false }
        if let id = bodyOperations[ticket.leaseID], bodyProbes[id] == ticket || pendingBodyProbe?.id == id {
            libraryProbeOwners.removeValue(forKey: id)
            return true
        }
        let probe = BodyProbe(id: UUID(), ticket: ticket)
        bodyOperations[ticket.leaseID] = probe.id
        bodyStates[ticket.leaseID] = .checking
        pendingBodyProbe = probe
        pumpBodyProbe()
        return isCurrent(ticket) && bodyOperations[ticket.leaseID] == probe.id
    }

    /// Revalidation withdraws only a cached display result. A pending/failed
    /// write remains explicit, and an old physical probe keeps its slot.
    @discardableResult
    func invalidateBodyStatus(ticket: AccessTicket) -> Bool {
        let change = bodyChangeID, operation = bodyOperations[ticket.leaseID]
        guard isCurrent(ticket), change == bodyChangeID, bodyOperations[ticket.leaseID] == operation,
              bodyStates[ticket.leaseID] != .pending, bodyStates[ticket.leaseID] != .failed,
              bodySaves[ticket.leaseID] == nil else { return false }
        let id = UUID()
        bodyOperations[ticket.leaseID] = id
        if invalidBodyReads.contains(ticket.leaseID) { bodyStates[ticket.leaseID] = .notDownloaded }
        else { bodyStates.removeValue(forKey: ticket.leaseID) }
        bodyProbeFailures.remove(ticket.leaseID)
        bodyCache.removeAll { $0.key == ticket.contentKey }
        if pendingBodyProbe?.ticket == ticket { pendingBodyProbe = nil }
        publishBodyChange()
        return ownsBodyOperation(id, ticket: ticket)
    }

    private func pumpBodyProbe() {
        guard !pumpingBodyProbes else { return }
        pumpingBodyProbes = true
        defer { pumpingBodyProbes = false }
        while bodyProbes.count < maximumBodyProbes {
            let probe: BodyProbe
            if let detail = pendingBodyProbe {
                pendingBodyProbe = nil; probe = detail
            } else if let library = nextLibraryBodyProbe() { probe = library }
            else if pendingBodyProbe != nil { continue }
            else { return }
            bodyProbes[probe.id] = probe.ticket
            guard ownsBodyOperation(probe.id, ticket: probe.ticket), bodyStates[probe.ticket.leaseID] == .checking else {
                bodyProbes.removeValue(forKey: probe.id); libraryProbeOwners.removeValue(forKey: probe.id)
                continue
            }
            storage.probe(probe.ticket.contentKey) { [weak self] result in
                self?.completeBodyProbe(probe, result: result)
            }
        }
    }

    private func nextLibraryBodyProbe() -> BodyProbe? {
        while var refresh = libraryRefresh, refresh.cursor < refresh.entries.count {
            guard model.snapshot.generation == refresh.handle.generation else {
                cancelLibraryBodyStatus(refresh.handle); return nil
            }
            let entry = refresh.entries[refresh.cursor]
            refresh.cursor += 1
            refresh.pendingEntries.removeValue(forKey: entry.membership.articleID)
            libraryRefresh = refresh
            guard model.isCurrent(entry.membership), access[entry.membership.articleID] == entry.access,
                  entry.access.flatMap({ bodyOperations[$0.leaseID] }) == entry.operation else { continue }
            guard let ticket = captureAccess(articleID: entry.membership.articleID),
                  ticket.membership.identifiesSameMembership(as: entry.membership),
                  libraryRefresh?.handle == refresh.handle, model.isCurrent(entry.membership) else { continue }
            guard bodyStates[ticket.leaseID] != .pending, bodyStates[ticket.leaseID] != .failed,
                  !invalidBodyReads.contains(ticket.leaseID), bodySaves[ticket.leaseID] == nil else { continue }
            if let id = bodyOperations[ticket.leaseID], bodyProbes[id] == ticket || pendingBodyProbe?.id == id { continue }
            if !refresh.force, let state = bodyStates[ticket.leaseID], state != .checking { continue }
            guard bodyOperations[ticket.leaseID] == entry.operation,
                  isCurrent(ticket), libraryRefresh?.handle == refresh.handle,
                  bodyOperations[ticket.leaseID] == entry.operation else { continue }
            if pendingBodyProbe != nil {
                // A detail may have arrived reentrantly through an authority
                // hook. Leave this member at the cursor and service it first.
                libraryRefresh?.cursor -= 1
                let captured = LibraryEntry(membership: entry.membership, access: ticket, operation: entry.operation)
                libraryRefresh?.entries[refresh.cursor - 1] = captured
                libraryRefresh?.pendingEntries[entry.membership.articleID] = captured
                return nil
            }
            let probe = BodyProbe(id: UUID(), ticket: ticket)
            bodyOperations[ticket.leaseID] = probe.id
            bodyStates[ticket.leaseID] = .checking
            bodyProbeFailures.remove(ticket.leaseID)
            bodyCache.removeAll { $0.key == ticket.contentKey }
            libraryProbeOwners[probe.id] = refresh.handle.id
            return probe
        }
        return nil
    }

    private func completeBodyProbe(_ probe: BodyProbe, result: Result<Bool, Error>) {
        guard bodyProbes[probe.id] == probe.ticket else { return }
        bodyProbes.removeValue(forKey: probe.id)
        libraryProbeOwners.removeValue(forKey: probe.id)
        defer { pumpBodyProbe() }
        guard ownsBodyOperation(probe.id, ticket: probe.ticket), bodyStates[probe.ticket.leaseID] == .checking,
              !invalidBodyReads.contains(probe.ticket.leaseID) else { return }
        let stored: Bool
        switch result {
        case .success(let value): stored = value; bodyProbeFailures.remove(probe.ticket.leaseID)
        case .failure: stored = false; bodyProbeFailures.insert(probe.ticket.leaseID)
        }
        bodyStates[probe.ticket.leaseID] = stored ? .available : .notDownloaded
        if !stored { bodyCache.removeAll { $0.key == probe.ticket.contentKey } }
        publishBodyChange()
    }

    private func withdrawBodyStatus(_ ticket: AccessTicket, operation: UUID?, invalidRead: Bool = false) {
        guard bodyOperations[ticket.leaseID] == operation, isCurrent(ticket),
              bodyOperations[ticket.leaseID] == operation else { return }
        if invalidRead { invalidBodyReads.insert(ticket.leaseID) }
        let removedProbeFailure = bodyProbeFailures.remove(ticket.leaseID) != nil
        bodyCache.removeAll { $0.key == ticket.contentKey }
        guard bodyStates[ticket.leaseID] != .pending, bodyStates[ticket.leaseID] != .failed,
              bodySaves[ticket.leaseID] == nil else { return }
        bodyOperations[ticket.leaseID] = UUID()
        if pendingBodyProbe?.ticket == ticket { pendingBodyProbe = nil }
        guard bodyStates[ticket.leaseID] != .notDownloaded else {
            if removedProbeFailure { publishBodyChange() }
            return
        }
        bodyStates[ticket.leaseID] = .notDownloaded
        publishBodyChange()
    }

    /// One finite queue keeps precisely the supplied memberships. Replacing it
    /// drops only waiting entries; an uncancellable fetch retains its physical
    /// slot until its actual callback, even after account or revision changes.
    @discardableResult
    func requestBodies(tickets: [AccessTicket], fetch: @escaping FetchBody) -> Bool {
        guard tickets.count <= FavoritesRecordCodec.maximumEntries else { return false }
        let id = UUID()
        libraryBodyDownloadID = id
        var seen = Set<UUID>()
        let unique = tickets.filter { seen.insert($0.leaseID).inserted }
        libraryBodyDownload = LibraryBodyDownload(id: id, tickets: unique, fetch: fetch,
            waitingLeaseIDs: Set(unique.map(\.leaseID)))
        publishBodyChange()
        guard libraryBodyDownloadID == id else { return false }
        pumpLibraryBodyDownloads()
        return libraryBodyDownloadID == id
    }

    private func pumpLibraryBodyDownloads() {
        guard !pumpingLibraryBodyDownloads else { return }
        pumpingLibraryBodyDownloads = true
        defer { pumpingLibraryBodyDownloads = false }
        while bodyFetches.count < maximumBodyFetches, var queue = libraryBodyDownload {
            guard queue.cursor < queue.tickets.count else {
                libraryBodyDownload = nil
                break
            }
            let ticket = queue.tickets[queue.cursor]
            let queueID = queue.id
            let cursor = queue.cursor
            queue.cursor += 1
            queue.waitingLeaseIDs.remove(ticket.leaseID)
            libraryBodyDownload = queue
            // Every hook below may replace the queue or switch the owner. The
            // shared single-request path checks this ID before starting I/O.
            let result = startBodyRequest(ticket: ticket, candidate: nil, fetch: queue.fetch,
                waitForCapacity: true, requestCurrent: { [weak self] in self?.libraryBodyDownloadID == queueID })
            if result == .waitingForCapacity, libraryBodyDownloadID == queue.id,
               libraryBodyDownload?.cursor == cursor + 1 {
                libraryBodyDownload?.cursor = cursor
                libraryBodyDownload?.waitingLeaseIDs.insert(ticket.leaseID)
                break
            }
            // Pending, available and failed transitions publish themselves.
            // A rejected/stale queued entry only needs its waiting status retired.
            if result == .rejected, libraryBodyDownloadID == queue.id { publishBodyChange() }
        }
    }

    /// A request belongs to the supplied original lease and revision. No new
    /// membership is captured by its completion or by an explicit retry.
    @discardableResult
    func requestBody(ticket: AccessTicket, candidate: Article? = nil, fetch: @escaping FetchBody) -> Bool {
        startBodyRequest(ticket: ticket, candidate: candidate, fetch: fetch,
            waitForCapacity: false, requestCurrent: { true }) == .accepted
    }

    private func startBodyRequest(ticket: AccessTicket, candidate: Article?, fetch: @escaping FetchBody,
                                  waitForCapacity: Bool, requestCurrent: @escaping @MainActor () -> Bool) -> BodyRequestResult {
        let change = bodyChangeID
        guard requestCurrent(), isCurrent(ticket), requestCurrent(), change == bodyChangeID,
              bodySaves[ticket.leaseID] == nil,
              !bodyFetches.values.contains(where: { $0.leaseID == ticket.leaseID }) else { return .rejected }
        // Admission uses actual work state, not the displayed queued marker.
        let state = bodyStates[ticket.leaseID] ?? .checking
        guard requestCurrent(), isCurrent(ticket), requestCurrent(), change == bodyChangeID,
              bodySaves[ticket.leaseID] == nil,
              !bodyFetches.values.contains(where: { $0.leaseID == ticket.leaseID }) else { return .rejected }
        // An explicit download action may validate the small index. Display
        // cache alone never suppresses a needed fetch after eviction/corruption.
        if state != .pending && state != .failed && !invalidBodyReads.contains(ticket.leaseID) {
            let operation = bodyOperations[ticket.leaseID]
            let stored = (try? storage.contains(ticket.contentKey)) == true
            guard requestCurrent(), isCurrent(ticket), requestCurrent(), change == bodyChangeID,
                  bodyOperations[ticket.leaseID] == operation else { return .rejected }
            if stored {
                let id = UUID(); bodyOperations[ticket.leaseID] = id
                bodyProbeFailures.remove(ticket.leaseID)
                if bodyStates[ticket.leaseID] != .available { bodyStates[ticket.leaseID] = .available; publishBodyChange() }
                return ownsBodyOperation(id, ticket: ticket) ? .accepted : .rejected
            }
            bodyCache.removeAll { $0.key == ticket.contentKey }
        }
        if let candidate {
            let stored = saveBody(candidate, ticket: ticket)
            // A rejected candidate is this explicit request's failure only if
            // no accepted save or reentrant replacement has superseded it.
            if !stored, requestCurrent(), change == bodyChangeID, isCurrent(ticket), requestCurrent(), change == bodyChangeID {
                bodyOperations[ticket.leaseID] = UUID()
                bodyStates[ticket.leaseID] = .failed; publishBodyChange()
            }
            return stored ? .accepted : .rejected
        }
        guard bodyFetches.count < maximumBodyFetches else {
            if waitForCapacity { return .waitingForCapacity }
            bodyOperations[ticket.leaseID] = UUID()
            bodyStates[ticket.leaseID] = .failed; publishBodyChange()
            return .rejected
        }
        let id = UUID()
        bodyOperations[ticket.leaseID] = id
        bodyFetches[id] = ticket
        bodyStates[ticket.leaseID] = .pending
        publishBodyChange()
        guard requestCurrent(), ownsBodyOperation(id, ticket: ticket), requestCurrent(), bodyFetches[id] == ticket else {
            bodyFetches.removeValue(forKey: id)
            pumpLibraryBodyDownloads()
            return .rejected
        }
        fetch(ticket.articleID) { [weak self] result in self?.completeBodyFetch(id, ticket: ticket, result: result) }
        return .accepted
    }

    @discardableResult
    func retryBody(ticket: AccessTicket, fetch: @escaping FetchBody) -> Bool {
        let change = bodyChangeID
        guard let state = bodyState(ticket: ticket), state == .failed || state == .notDownloaded,
              change == bodyChangeID else { return false }
        return requestBody(ticket: ticket, fetch: fetch)
    }

    private func completeBodyFetch(_ id: UUID, ticket: AccessTicket, result: Result<Article, Error>) {
        guard bodyFetches[id] == ticket else { return }
        bodyFetches.removeValue(forKey: id)
        defer { pumpLibraryBodyDownloads() }
        guard ownsBodyOperation(id, ticket: ticket) else { return }
        switch result {
        case .success(let article):
            let matching = matches(article, ticket: ticket)
            guard ownsBodyOperation(id, ticket: ticket) else { return }
            guard matching else { bodyStates[ticket.leaseID] = .failed; publishBodyChange(); return }
            _ = saveBody(article, ticket: ticket)
        case .failure:
            bodyStates[ticket.leaseID] = .failed
            publishBodyChange()
        }
    }

    private func ownsBodyOperation(_ id: UUID, ticket: AccessTicket) -> Bool {
        guard bodyOperations[ticket.leaseID] == id, isCurrent(ticket) else { return false }
        return bodyOperations[ticket.leaseID] == id
    }

    private func publishBodyChange() {
        bodyChangeID = UUID()
        bodyChangeSubject.send(())
    }

    @discardableResult
    func saveBody(_ article: Article, ticket: AccessTicket) -> Bool {
        let change = bodyChangeID
        guard isCurrent(ticket), change == bodyChangeID, bodySaves[ticket.leaseID] == nil else { return false }
        let matching = matches(article, ticket: ticket)
        guard isCurrent(ticket), change == bodyChangeID, bodySaves[ticket.leaseID] == nil else { return false }
        // Independent detail callbacks do not own a fetch token. Invalid or
        // mismatched data must not invalidate a good body or another fetch.
        guard matching else { return false }
        let id = UUID()
        // An explicit save (including the detail loader's) supersedes the
        // logical result of an older fetch without freeing its physical slot.
        bodyOperations[ticket.leaseID] = id
        bodySaves[ticket.leaseID] = id
        defer { if bodySaves[ticket.leaseID] == id { bodySaves.removeValue(forKey: ticket.leaseID) } }
        bodyStates[ticket.leaseID] = .pending
        publishBodyChange()
        guard ownsBodyOperation(id, ticket: ticket), bodySaves[ticket.leaseID] == id else { return false }
        do { try storage.write(ticket.contentKey, article) }
        catch {
            if ownsBodyOperation(id, ticket: ticket) { bodyStates[ticket.leaseID] = .failed; publishBodyChange() }
            return false
        }
        guard ownsBodyOperation(id, ticket: ticket), bodySaves[ticket.leaseID] == id else { return false }
        let stored = (try? storage.contains(ticket.contentKey)) == true
        guard ownsBodyOperation(id, ticket: ticket), bodySaves[ticket.leaseID] == id else { return false }
        guard stored else { bodyStates[ticket.leaseID] = .failed; publishBodyChange(); return false }
        remember(article, key: ticket.contentKey)
        effects.cacheImages(article, ticket.contentKey)
        guard ownsBodyOperation(id, ticket: ticket), bodySaves[ticket.leaseID] == id else { return false }
        _ = cacheAudio(ticket)
        guard ownsBodyOperation(id, ticket: ticket), bodySaves[ticket.leaseID] == id else { return false }
        invalidBodyReads.remove(ticket.leaseID)
        bodyProbeFailures.remove(ticket.leaseID)
        bodyStates[ticket.leaseID] = .available
        publishBodyChange()
        return ownsBodyOperation(id, ticket: ticket)
    }

    /// Ephemeral proof captured before one explicit favorite removal. It grants
    /// no access after that mutation and cannot be transferred to another owner.
    struct DownloadRemovalTicket {
        fileprivate let owner: ObjectIdentifier
        fileprivate let access: AccessTicket
        fileprivate let contentKeys: Set<String>
        fileprivate let audio: PodcastAudioAsset?
    }

    func captureDownloadRemoval(articleID: String) -> DownloadRemovalTicket? {
        guard let ticket = captureAccess(articleID: articleID), isCurrent(ticket) else { return nil }
        let audio: PodcastAudioAsset?
        if let held = pins[ticket.pinKey], held.ticket == ticket { audio = held.asset }
        else { audio = acceptedAudioAsset(ticket) }
        guard isCurrent(ticket) else { return nil }
        let keys = Set(bodyCache.filter { $0.article.id == articleID }.map(\.key)).union([ticket.contentKey])
        return DownloadRemovalTicket(owner: ObjectIdentifier(self), access: ticket, contentKeys: keys, audio: audio)
    }

    /// Only the accepted local removal may evict its exact downloaded content.
    /// Cloud changes, withdrawal and account transitions retain ordinary release.
    @discardableResult
    func discardDownloads(_ removal: DownloadRemovalTicket, mutation: FavoritesModel.Mutation) -> Bool {
        let ticket = removal.access
        func current() -> Bool {
            removal.owner == ObjectIdentifier(self) && !mutation.enabled
                && mutation.articleID == ticket.articleID
                && mutation.namespace == ticket.membership.namespace
                && mutation.generation == ticket.membership.generation
                && model.isCurrent(mutation) && model.membershipTicket(articleID: ticket.articleID) == nil
        }
        guard current() else { return false }
        if access[ticket.articleID] == ticket { access.removeValue(forKey: ticket.articleID) }
        release(ticket)
        guard current() else { return false }
        bodyCache.removeAll { $0.article.id == ticket.articleID }
        var removedBodies = true
        for key in removal.contentKeys.sorted() {
            guard current() else { return false }
            do { try storage.remove(key) } catch { removedBodies = false }
            guard current() else { return false }
            effects.removeImages(key)
        }
        guard current() else { return false }
        if let audio = removal.audio { effects.removeAudio(audio) }
        return removedBodies && current()
    }

    func synchronizeCurrentMembership() {
        guard !synchronizing else { return }
        synchronizing = true
        defer { synchronizing = false }
        let generation = model.snapshot.generation
        let existing = Array(access.values)
        for old in existing where !permitsAccountAccess || !model.isCurrent(old.membership) || !permitsBody(old.membership.article) {
            if access[old.articleID] == old { access.removeValue(forKey: old.articleID) }
            release(old)
        }
        guard model.snapshot.generation == generation else { return }
        for article in model.snapshot.articles {
            guard model.snapshot.generation == generation else { return }
            guard let ticket = captureAccess(articleID: article.id) else { continue }
            // Lightweight metadata images only: never preload every full body.
            effects.cacheImages(article, ticket.contentKey)
            guard isCurrent(ticket) else { continue }
            _ = cacheAudio(ticket)
        }
    }

    /// Resolves an accepted descriptor now. Missing or changed authority drops
    /// only this member's old lease; it never relabels existing public bytes.
    @discardableResult
    func cacheAudio(_ ticket: AccessTicket, retryIfMissing: Bool = true) -> Bool {
        guard isCurrent(ticket) else { return false }
        guard ArticleAudioLanguagePolicy.requiresAudio(for: ticket.membership.article) else {
            if let retry = retries.removeValue(forKey: ticket.leaseID) { retry.cancel?() }
            releasePin(ticket)
            return false
        }
        guard let asset = acceptedAudioAsset(ticket) else {
            releasePin(ticket)
            if retryIfMissing, isCurrent(ticket) { scheduleAudioRetry(ticket) }
            return false
        }
        return pin(asset, ticket: ticket)
    }

    /// Deferred work retains the original descriptor as well as membership.
    /// A replacement manifest cannot silently give that operation a new asset.
    @discardableResult
    func cacheAudio(_ ticket: AccessTicket, asset: PodcastAudioAsset) -> Bool {
        guard acceptedAudioAsset(ticket) == asset else { return false }
        return pin(asset, ticket: ticket)
    }

    func acceptedAudioAsset(_ ticket: AccessTicket) -> PodcastAudioAsset? {
        guard isCurrent(ticket), ArticleAudioLanguagePolicy.requiresAudio(for: ticket.membership.article) else { return nil }
        let asset = effects.audioAsset(ticket.membership.article)
        guard isCurrent(ticket), let asset, asset.canonicalArticleID == ticket.articleID,
              asset.isCompatible(withTextRevision: ticket.contentRevision) else { return nil }
        return asset
    }

    private func pin(_ asset: PodcastAudioAsset, ticket: AccessTicket) -> Bool {
        guard acceptedAudioAsset(ticket) == asset else { return false }
        let request = AudioPinRequest(leaseID: ticket.leaseID, asset: asset)
        guard audioPinRequests.insert(request).inserted else {
            return pins[ticket.pinKey]?.ticket == ticket && pins[ticket.pinKey]?.asset == asset
        }
        defer { audioPinRequests.remove(request) }
        if pins[ticket.pinKey]?.ticket != ticket || pins[ticket.pinKey]?.asset != asset {
            if let previous = pins.removeValue(forKey: ticket.pinKey) {
                effects.releaseAudio(previous.ticket.pinKey, previous.ticket.leaseID, previous.asset)
                guard acceptedAudioAsset(ticket) == asset else { return false }
            }
            pins[ticket.pinKey] = (ticket, asset)
        }
        // A retained pin is not proof of a completed download. Reassert the same
        // lease so a later request can retry failure; the cache coalesces pending
        // work and reuses valid bytes. Only synchronous identical reentry stops here.
        effects.pinAudio(ticket.pinKey, ticket.leaseID, asset)
        guard acceptedAudioAsset(ticket) == asset,
              pins[ticket.pinKey]?.ticket == ticket, pins[ticket.pinKey]?.asset == asset else {
            if pins[ticket.pinKey]?.ticket == ticket, pins[ticket.pinKey]?.asset == asset { pins.removeValue(forKey: ticket.pinKey) }
            effects.releaseAudio(ticket.pinKey, ticket.leaseID, asset)
            return false
        }
        return true
    }

    func audioDownloaded(articleID: String, expectedRevision: String? = nil, expectedAsset: PodcastAudioAsset? = nil) -> Bool {
        guard let ticket = captureAccess(articleID: articleID),
              expectedRevision.map({ $0 == ticket.contentRevision }) ?? true,
              let asset = acceptedAudioAsset(ticket), expectedAsset.map({ $0 == asset }) ?? true else { return false }
        let cached = effects.audioIsCached(asset)
        return cached && acceptedAudioAsset(ticket) == asset
    }

    /// Presentation reads existing in-memory state only. Membership, source
    /// authority and actual cached bytes remain separate required conditions.
    func audioState(ticket: AccessTicket) -> AudioState? {
        guard isCurrent(ticket), ArticleAudioLanguagePolicy.requiresAudio(for: ticket.membership.article) else { return nil }
        guard let asset = acceptedAudioAsset(ticket) else {
            return isCurrent(ticket) ? .waitingForPublication : nil
        }
        let state = effects.audioState?(asset) ?? (effects.audioIsCached(asset) ? .available : .waiting)
        guard isCurrent(ticket), acceptedAudioAsset(ticket) == asset else { return nil }
        // A progress provider cannot manufacture the existing byte proof.
        if state == .available {
            let cached = effects.audioIsCached(asset)
            // Even a negative proof callback can synchronously revoke this
            // owner or replace its descriptor. Never return old presentation.
            guard isCurrent(ticket), acceptedAudioAsset(ticket) == asset else { return nil }
            if !cached { return .checking }
        }
        guard isCurrent(ticket), acceptedAudioAsset(ticket) == asset else { return nil }
        return state
    }

    /// Progress belongs to the current accepted asset and transfer only. It is
    /// presentation, never authority to mark either local component available.
    func audioProgress(ticket: AccessTicket) -> Double? {
        guard isCurrent(ticket), let asset = acceptedAudioAsset(ticket),
              audioState(ticket: ticket) == .downloading,
              let value = effects.audioProgress?(asset), value.isFinite,
              (0...1).contains(value), isCurrent(ticket),
              acceptedAudioAsset(ticket) == asset,
              audioState(ticket: ticket) == .downloading,
              isCurrent(ticket), acceptedAudioAsset(ticket) == asset else { return nil }
        return value
    }

    var libraryOfflineSummary: LibraryOfflineSummary {
        let snapshot = model.snapshot
        let originalBodyChange = bodyChangeID
        var ready = 0, text = 0, audio = 0, pending = 0, disabled = 0, waiting = 0, failed = 0, storage = 0
        for article in snapshot.articles {
            guard let ticket = access[article.id], isCurrent(ticket) else { continue }
            let body = displayedBodyState(ticket)
            let sound = audioState(ticket: ticket)
            if body == .available { text += 1 }
            if sound == .available { audio += 1 }
            if sound == .checking || sound == .waiting || sound == .downloading { pending += 1 }
            if sound == .disabled { disabled += 1 }
            if body == .available,
               sound == .available || !ArticleAudioLanguagePolicy.requiresAudio(for: article) { ready += 1 }
            if sound == .waitingForPublication { waiting += 1 }
            if body == .failed || sound == .failed { failed += 1 }
            if sound == .storageLimit { storage += 1 }
        }
        guard model.snapshot.generation == snapshot.generation,
              model.snapshot.revision == snapshot.revision, bodyChangeID == originalBodyChange else {
            return .init(total: model.snapshot.articles.count, ready: 0, textAvailable: 0,
                         audioAvailable: 0, audioPending: 0, audioDisabled: 0, awaitingAudio: 0, failed: 0, storageLimited: 0, isLoaded: false)
        }
        return .init(total: snapshot.articles.count, ready: ready, textAvailable: text,
                     audioAvailable: audio, audioPending: pending, audioDisabled: disabled, awaitingAudio: waiting, failed: failed,
                     storageLimited: storage, isLoaded: model.canChangeSelection)
    }

    /// Context/local cleanup releases only exact old leases. Public bytes and
    /// another owner's pins remain; this is not a global purge or account delete.
    func releaseCurrentAccess() {
        libraryBodyDownloadID = UUID()
        libraryBodyDownload = nil
        let previous = Array(access.values)
        let previousRefresh = libraryRefresh?.handle
        access = [:]
        bodyCache = []
        if let previousRefresh { cancelLibraryBodyStatus(previousRefresh) }
        for ticket in previous { release(ticket) }
    }

    func releaseArticleAccess(articleID: String) {
        guard let ticket = access.removeValue(forKey: articleID) else { return }
        release(ticket)
    }

    private func release(_ ticket: AccessTicket) {
        let hadBodyState = bodyStates.removeValue(forKey: ticket.leaseID) != nil
        invalidBodyReads.remove(ticket.leaseID)
        bodyProbeFailures.remove(ticket.leaseID)
        bodyOperations.removeValue(forKey: ticket.leaseID)
        if pendingBodyProbe?.ticket == ticket { pendingBodyProbe = nil }
        if hadBodyState { publishBodyChange() }
        if let retry = retries.removeValue(forKey: ticket.leaseID) { retry.cancel?() }
        releasePin(ticket)
    }

    private func releasePin(_ ticket: AccessTicket) {
        if let pin = pins[ticket.pinKey], pin.ticket == ticket {
            pins.removeValue(forKey: ticket.pinKey)
            effects.releaseAudio(ticket.pinKey, ticket.leaseID, pin.asset)
        }
    }

    private func scheduleAudioRetry(_ ticket: AccessTicket) {
        guard isCurrent(ticket), retries[ticket.leaseID] == nil else { return }
        let id = UUID()
        retries[ticket.leaseID] = (id, nil)
        let cancel = effects.scheduleRetry(2) { [weak self] in
            guard let self, self.retries[ticket.leaseID]?.id == id else { return }
            self.retries.removeValue(forKey: ticket.leaseID)
            _ = self.cacheAudio(ticket, retryIfMissing: false)
        }
        if retries[ticket.leaseID]?.id == id, isCurrent(ticket) { retries[ticket.leaseID] = (id, cancel) }
        else { cancel() }
    }

    private func remember(_ article: Article, key: String) {
        bodyCache.removeAll { $0.key == key }
        bodyCache.append((key, article))
        if bodyCache.count > 2 { bodyCache.removeFirst(bodyCache.count - 2) }
    }

    private func matches(_ article: Article, ticket: AccessTicket) -> Bool {
        article.id == ticket.articleID && article.bodyRevision == ticket.contentRevision && permitsBody(article)
            && article.content?.isEmpty == false && (article.content?.utf8.count ?? 0) <= Self.maximumBodyBytes
    }

    private static func digest(_ values: [String]) -> String {
        let input = values.map { "\($0.utf8.count):\($0)" }.joined()
        return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
