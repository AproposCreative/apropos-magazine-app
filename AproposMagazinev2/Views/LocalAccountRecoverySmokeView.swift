#if DEBUG && targetEnvironment(simulator)
import Combine
import FirebaseCore
import SwiftUI

/// Local files only; the hold affects the actual journal's utility-queue remove.
/// Evidence is read on an explicit task and cached before SwiftUI renders it.
private final class LocalRecoveryFavoritesDisk: @unchecked Sendable {
    struct Evidence: Sendable {
        var ownV1 = true, ownV2 = true, otherUnchanged = true, guestUnchanged = true
    }
    private let lock = NSLock(), release = DispatchSemaphore(value: 0)
    private var holdNext = true, failNext = false, held = false, starts = 0
    private var changed: (@Sendable () -> Void)?
    private var expectedOther: [URL: Data] = [:], expectedGuest: [URL: Data] = [:]
    let directory: URL
    let owner: FavoritesNamespace
    init(directory: URL, owner: FavoritesNamespace) { self.directory = directory; self.owner = owner }
    var isHeld: Bool { lock.withLock { held } }
    var removeStarts: Int { lock.withLock { starts } }
    func configureFailure(_ value: Bool) { lock.withLock { failNext = value } }
    func onChange(_ callback: @escaping @Sendable () -> Void) { lock.withLock { changed = callback } }
    func v1(_ namespace: FavoritesNamespace) -> URL { directory.appendingPathComponent(namespace.storageKey + ".legacy") }
    func v2(_ namespace: FavoritesNamespace) -> URL { directory.appendingPathComponent(namespace.recordBinding + ".json") }
    func seed(_ records: [(FavoritesNamespace, Data, Data)]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (namespace, legacy, current) in records {
            try legacy.write(to: v1(namespace), options: .atomic)
            try current.write(to: v2(namespace), options: .atomic)
            if namespace == .guest { expectedGuest = [v1(namespace): legacy, v2(namespace): current] }
            else if namespace != owner { expectedOther = [v1(namespace): legacy, v2(namespace): current] }
        }
    }
    func legacyRead(_ namespace: FavoritesNamespace) throws -> Data? {
        let url = v1(namespace)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
    func legacyDelete(_ namespace: FavoritesNamespace, expected: Data) throws {
        guard try legacyRead(namespace) == expected else { throw FavoritesJournalFailure.staleRevision }
        let fail = lock.withLock { let original = failNext; failNext = false; return original }
        if fail { throw FavoritesJournalFailure.writeFailed }
        try FileManager.default.removeItem(at: v1(namespace))
    }
    func remove(_ url: URL) throws {
        let hold = lock.withLock { () -> Bool in
            let original = holdNext
            holdNext = false; held = original; starts += 1
            return original
        }
        let callback = lock.withLock { changed }
        callback?()
        defer { lock.withLock { held = false }; callback?() }
        if hold, release.wait(timeout: .now() + 120) != .success { throw FavoritesJournalFailure.writeFailed }
        try FileManager.default.removeItem(at: url)
    }
    func releaseRemove() { release.signal() }
    func evidence() -> Evidence {
        Evidence(ownV1: FileManager.default.fileExists(atPath: v1(owner).path),
            ownV2: FileManager.default.fileExists(atPath: v2(owner).path),
            otherUnchanged: expectedOther.allSatisfy { (try? Data(contentsOf: $0.key)) == $0.value },
            guestUnchanged: expectedGuest.allSatisfy { (try? Data(contentsOf: $0.key)) == $0.value })
    }
}

/// Local resume bytes with a physically held store write. Diagnostics read the
/// file independently of Storage.read, so they cannot consume the injected
/// readback failure or accidentally reopen the ordinary reader's closed path.
private final class LocalRecoveryResumeDisk: @unchecked Sendable {
    struct Evidence: Sendable {
        var ownerCount = 2, otherUnchanged = true, guestUnchanged = true
    }
    private let lock = NSLock(), release = DispatchSemaphore(value: 0)
    private var holdNext = true, failReadback = false, readMustFail = false
    private var held = false, starts = 0, readFailures = 0
    private var changed: (@Sendable () -> Void)?
    private var expectedOther: [ReaderResumeRecord.Entry] = [], expectedGuest: [ReaderResumeRecord.Entry] = []
    let file: URL
    let owner = ReadingHistoryContext.confirmed(userID: "local-reader-A").namespace!.recordBinding
    init(file: URL) { self.file = file }
    var isHeld: Bool { lock.withLock { held } }
    var writeStarts: Int { lock.withLock { starts } }
    var failureCount: Int { lock.withLock { readFailures } }
    func onChange(_ callback: @escaping @Sendable () -> Void) { lock.withLock { changed = callback } }
    func seed(failReadback: Bool) throws {
        let other = ReadingHistoryContext.confirmed(userID: "local-reader-B").namespace!.recordBinding
        let entries = [owner, owner, other, ReadingHistoryNamespace.guest.recordBinding].enumerated().map { index, binding in
            ReaderResumeRecord.Entry(owner: binding,
                source: ReaderResumeIdentity(articleID: "resume-article-\(index)", sourceRevision: "local-r1",
                    html: "<p>Et lokalt læseafsnit \(index)</p>")!,
                anchor: ReaderResumeAnchor(index: index + 1, fingerprint: "1234abcd"))
        }
        expectedOther = entries.filter { $0.owner == other }
        expectedGuest = entries.filter { $0.owner == ReadingHistoryNamespace.guest.recordBinding }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ReaderResumeRecord.encode(.init(entries: entries)).write(to: file, options: .atomic)
        lock.withLock { self.failReadback = failReadback }
    }
    func read() throws -> Data? {
        let shouldFail = lock.withLock { () -> Bool in
            guard readMustFail else { return false }
            readMustFail = false; readFailures += 1; return true
        }
        if shouldFail { throw ReaderResumeRecord.Failure.unavailable }
        return try Data(contentsOf: file)
    }
    func write(_ data: Data) throws {
        let original = try ReaderResumeRecord.decode(Data(contentsOf: file))
        let target = try ReaderResumeRecord.decode(data)
        let removesOwner = original.entries.contains { $0.owner == owner }
            && !target.entries.contains { $0.owner == owner }
        let hold = lock.withLock { () -> Bool in
            guard removesOwner else { return false }
            starts += 1
            let value = holdNext; holdNext = false; held = value; return value
        }
        let callback = lock.withLock { changed }
        callback?()
        defer { lock.withLock { held = false }; callback?() }
        if hold, release.wait(timeout: .now() + 120) != .success { throw ReaderResumeRecord.Failure.unavailable }
        try data.write(to: file, options: .atomic)
        lock.withLock {
            if removesOwner && failReadback { failReadback = false; readMustFail = true }
        }
    }
    func releaseWrite() { release.signal() }
    func evidence() -> Evidence {
        guard let bytes = try? Data(contentsOf: file), let value = try? ReaderResumeRecord.decode(bytes) else {
            return Evidence(ownerCount: -1, otherUnchanged: false, guestUnchanged: false)
        }
        return Evidence(ownerCount: value.entries.filter { $0.owner == owner }.count,
            otherUnchanged: value.entries.filter { $0.owner == expectedOther.first?.owner } == expectedOther,
            guestUnchanged: value.entries.filter { $0.owner == ReadingHistoryNamespace.guest.recordBinding } == expectedGuest)
    }
}

/// The production progress adapter is synchronous and MainActor-bound. This
/// local dictionary uses that exact boundary; no held async write or player is
/// invented. Only the original owner's first completed write fails readback.
@MainActor
private final class LocalRecoveryPodcastStorage {
    let owner = PodcastProgressContext.confirmed(userID: "local-reader-A").namespace!
    private let other = PodcastProgressContext.confirmed(userID: "local-reader-B").namespace!
    private var records: [String: Data] = [:]
    private var expectedOther: Data?, expectedGuest: Data?
    private var expectedLegacy: [String: Data] = [:]
    private var failReadback = false, readMustFail = false
    private(set) var factoryCalls = 0, reads = 0, writes = 0, removalWrites = 0, readFailures = 0
    private(set) var ownerCount = 2

    func seed(failReadback: Bool) throws {
        for (index, namespace) in [owner, other, .guest].enumerated() {
            let entries = (0..<(namespace == owner ? 2 : 1)).map { item in
                PodcastProgressRecord.Entry(episodeID: "local-episode-\(index)-\(item)",
                    articleID: "local-audio-article-\(index)-\(item)",
                    positionSeconds: Double(42 + item * 10), durationSeconds: 600)
            }
            let record = PodcastProgressRecord(entries: entries, lastEpisodeID: entries.last?.episodeID)
            records[namespace.storageKey] = try PodcastProgressRecordCodec.encode(record, namespace: namespace)
        }
        expectedOther = records[other.storageKey]
        expectedGuest = records[PodcastProgressNamespace.guest.storageKey]
        // Opaque unowned legacy values are preserved, never adopted as A.
        expectedLegacy = ["podcast_progress_legacy-episode": Data("42".utf8),
            "podcast_last_episode_id": Data("legacy-episode".utf8),
            "podcast_last_article_id": Data("legacy-article".utf8)]
        records.merge(expectedLegacy) { original, _ in original }
        self.failReadback = failReadback
    }
    var storage: PodcastPlaybackProgressStore.Storage {
        factoryCalls += 1
        return .init(read: { [self] namespace in
            reads += 1
            if namespace == owner && readMustFail {
                readMustFail = false; readFailures += 1
                throw PodcastProgressRecordCodec.Failure.invalidRecord
            }
            return records[namespace.storageKey]
        }, write: { [self] namespace, data in
            let value = try PodcastProgressRecordCodec.decode(data, namespace: namespace)
            writes += 1
            records[namespace.storageKey] = data
            if namespace == owner {
                let removesPositions = ownerCount > 0 && value.entries.isEmpty
                ownerCount = value.entries.count
                if removesPositions {
                    removalWrites += 1
                    if failReadback { failReadback = false; readMustFail = true }
                }
            }
        })
    }
    var otherUnchanged: Bool { records[other.storageKey] == expectedOther }
    var guestUnchanged: Bool { records[PodcastProgressNamespace.guest.storageKey] == expectedGuest }
    var legacyUnchanged: Bool { expectedLegacy.allSatisfy { records[$0.key] == $0.value } }
}

/// A single shared introduction draft and its separate cleanup sidecar. Seed
/// through the actual model; source observations are cached during explicit
/// storage effects so rendering cannot consume an injected readback failure.
@MainActor
private final class LocalRecoveryIntroductionStorage {
    private var source: Data?, cleanup: Data?, guest: Data?, expectedGuest: Data?
    private var failReadback = false, readMustFail = false
    private var sourceOwner: String?
    private(set) var reads = 0, writes = 0, cleanupReads = 0, cleanupWrites = 0, clearWrites = 0, readFailures = 0
    private(set) var topicCount = 0, completed = false, replaying = false
    private(set) var step = "unknown"
    var ownerCleared: Bool { sourceOwner == nil }
    var guestUnchanged: Bool { guest == expectedGuest }
    private enum Failure: Error { case seed, readback, malformed }

    var storage: ReaderIntroductionStorage {
        .init(read: { [self] in
            reads += 1
            if readMustFail { readMustFail = false; readFailures += 1; throw Failure.readback }
            return source
        }, write: { [self] bytes in
            let oldOwner = sourceOwner
            guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  let ids = object["selectedTopicIDs"] as? [String], let done = object["completed"] as? Bool,
                  let replay = object["replaying"] as? Bool, let nextStep = object["step"] as? String else { throw Failure.malformed }
            source = bytes; writes += 1
            sourceOwner = object["draftOwner"] as? String
            topicCount = ids.count; completed = done; replaying = replay; step = nextStep
            if oldOwner != nil && sourceOwner == nil && ids.isEmpty {
                clearWrites += 1
                if failReadback { failReadback = false; readMustFail = true }
            }
        }, cleanup: .init(read: { [self] in cleanupReads += 1; return cleanup },
            write: { [self] bytes in cleanupWrites += 1; cleanup = bytes }))
    }
    func seed(failReadback: Bool) throws {
        let canonical = CanonicalSessionState()
        canonical.adopt(ReaderAccountSession(uid: "local-reader-A", email: "local@example.invalid", isEmailVerified: true))
        let model = ReaderIntroductionModel(storage: storage)
        guard model.bindContext(canonical.contextTicket(), isCurrent: canonical.isCurrent), model.start(),
              model.complete(), model.replay(), model.advance(), model.setSelectedTopicIDs(["film", "kultur"]) else { throw Failure.seed }
        let guestCanonical = CanonicalSessionState(); guestCanonical.adopt(nil)
        let guestModel = GuestReaderInterestsModel(storage: .init(read: { [self] in guest }, write: { [self] in guest = $0 }))
        guard guestModel.start(), guestModel.save(["gaming"], context: guestCanonical.contextTicket(),
            isCurrent: guestCanonical.isCurrent) else { throw Failure.seed }
        expectedGuest = guest
        reads = 0; writes = 0; cleanupReads = 0; cleanupWrites = 0; clearWrites = 0; readFailures = 0
        self.failReadback = failReadback
    }
}

/// Injected effects for the actual KVS-backed history model. There is no KVS
/// instance or synchronization here; a successful readback is local evidence.
@MainActor
private final class LocalRecoveryHistoryStorage {
    let owner = ReadingHistoryContext.confirmed(userID: "local-reader-A").namespace!
    private let other = ReadingHistoryContext.confirmed(userID: "local-reader-B").namespace!
    private var records: [String: Data] = [:], metadata: Data?
    private var expectedOther: Data?, expectedGuest: Data?
    private var expectedLegacy: [String: Data] = [:]
    private var failReadback = false, readMustFail = false
    private(set) var reads = 0, writes = 0, metadataReads = 0, metadataWrites = 0
    private(set) var removalWrites = 0, readFailures = 0, ownerCount = 2
    var factoryCalls = 0, synchronizations = 0, profileWrites = 0
    var timers: [@MainActor () -> Void] = []
    var callbacks: [@MainActor (ReadingHistoryRuntime.ExternalEvent) -> Void] = []
    private(set) var staleProbeCount = 0, staleEffectsDenied = true

    func seed(failReadback: Bool) throws {
        for (index, namespace) in [owner, other, .guest].enumerated() {
            let entries = (0..<(namespace == owner ? 2 : 1)).map { item in
                ReadingHistoryRecord.Entry(articleID: "local-history-\(index)-\(item)", read: true, progress: 0.2)
            }
            records[namespace.storageKey] = try ReadingHistoryRecordCodec.encode(.init(entries: entries), namespace: namespace)
        }
        expectedOther = records[other.storageKey]
        expectedGuest = records[ReadingHistoryNamespace.guest.storageKey]
        expectedLegacy = ["readArticleIds": Data("unowned legacy read IDs".utf8),
                          "readingProgress": Data("unowned legacy progress".utf8)]
        records.merge(expectedLegacy) { original, _ in original }
        self.failReadback = failReadback
    }
    private func read(_ namespace: ReadingHistoryNamespace) throws -> Data? {
        reads += 1
        if namespace == owner && readMustFail {
            readMustFail = false; readFailures += 1
            throw ReadingHistoryRecordCodec.Failure.invalidRecord
        }
        return records[namespace.storageKey]
    }
    private func write(_ namespace: ReadingHistoryNamespace, _ bytes: Data) throws {
        let record = try ReadingHistoryRecordCodec.decode(bytes, namespace: namespace)
        writes += 1; records[namespace.storageKey] = bytes
        if namespace == owner {
            let removesHistory = ownerCount > 0 && record.entries.isEmpty
            ownerCount = record.entries.count
            if removesHistory {
                removalWrites += 1
                if failReadback { failReadback = false; readMustFail = true }
            }
        }
    }
    var storage: ReadingHistoryModel.Storage {
        .init(read: { [self] in try read($0) }, write: { [self] in try write($0, $1) })
    }
    var cleanupCapability: ReadingHistoryModel.Storage.Cleanup {
        .init(readSource: { [self] in try read($0) }, writeSource: { [self] in try write($0, $1) },
            readMetadata: { [self] in metadataReads += 1; return metadata },
            writeMetadata: { [self] in metadataWrites += 1; metadata = $0 })
    }
    func resetSourceCountersAfterOriginalSetup() { reads = 0; writes = 0 }
    func exerciseOldCallbacks(runtime: ReadingHistoryRuntime, ticket: ReadingHistoryModel.ArticleTicket) {
        let before = [reads, writes, synchronizations, profileWrites, factoryCalls]
        let originalRecords = records
        timers.forEach { $0() }
        callbacks.forEach {
            $0(.changed(keys: [owner.storageKey])); $0(.accountChanged); $0(.quotaViolation)
        }
        runtime.markRead(ticket); runtime.flushAcceptedEdits(); runtime.prepareIfNeeded()
        runtime.changeAccountContext(userID: "local-reader-B"); runtime.changeAccountContext(userID: "local-reader-A")
        let stale = runtime.model.saveProgress(0.9, ticket: ticket) == .stale
        staleEffectsDenied = staleEffectsDenied && stale && records == originalRecords
            && before == [reads, writes, synchronizations, profileWrites, factoryCalls]
        staleProbeCount += 1
    }
    var otherUnchanged: Bool { records[other.storageKey] == expectedOther }
    var guestUnchanged: Bool { records[ReadingHistoryNamespace.guest.storageKey] == expectedGuest }
    var legacyUnchanged: Bool { expectedLegacy.allSatisfy { records[$0.key] == $0.value } }
}

/// Actual account content -> Auth-owned recovery flow -> email reauthentication
/// -> original HTTP adapter. Every effect is local and the startup stays closed.
/// Memory-only implementation of the actual private installation store. Reading
/// recovery never calls prepare, creates identity, or changes this fixture record.
private final class LocalRecoveryPushStorage: @unchecked Sendable, PushInstallationRecordStore {
    private let lock = NSLock()
    private var data: Data?
    private var reads = 0, writes = 0, replacements = 0
    static let installationID = "4da6c391-e048-4e4f-9c75-80c248ca258b"
    func seed(appID: String, acknowledged: Bool) throws {
        let binding = PushAcknowledgedInstallationBinding(schemaVersion: 1,
            installationId: Self.installationID, appId: appID, ownerUID: "local-reader-A",
            ownerEpoch: 4, revision: 9, clientRevision: 17, status: .active)
        let record = PushInstallationRecord(installationId: Self.installationID,
            key: String(repeating: "a", count: 64), revision: 17,
            intentHash: String(repeating: "1", count: 64), revisionStartedAt: Date(timeIntervalSince1970: 1_800_000_000),
            acknowledgedBinding: acknowledged ? binding : nil)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = .sortedKeys
        let bytes = try encoder.encode(record)
        lock.lock(); defer { lock.unlock() }; data = bytes
    }
    func replaceWithOtherAccount(appID: String) throws {
        let binding = PushAcknowledgedInstallationBinding(schemaVersion: 1,
            installationId: Self.installationID, appId: appID, ownerUID: "local-reader-B",
            ownerEpoch: 5, revision: 10, clientRevision: 18, status: .active)
        let record = PushInstallationRecord(installationId: Self.installationID,
            key: String(repeating: "a", count: 64), revision: 18,
            intentHash: String(repeating: "2", count: 64), revisionStartedAt: Date(timeIntervalSince1970: 1_800_000_001),
            acknowledgedBinding: binding)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = .sortedKeys
        let bytes = try encoder.encode(record)
        lock.lock(); defer { lock.unlock() }; data = bytes; replacements += 1
    }
    func transaction(_ update: (Data?) throws -> Data) throws -> Data {
        lock.lock(); defer { lock.unlock() }; reads += 1
        let next = try update(data)
        if next != data { data = next; writes += 1 }
        return next
    }
    var evidence: [String: Any] {
        lock.lock(); defer { lock.unlock() }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let record = data.flatMap { try? decoder.decode(PushInstallationRecord.self, from: $0) }
        return ["pushVaultReads": reads, "pushVaultWrites": writes, "pushVaultReplacements": replacements,
                "pushVaultOwner": record?.acknowledgedBinding?.ownerUID ?? "",
                "pushVaultRevision": record?.revision ?? 0, "pushVaultHasACK": record?.acknowledgedBinding != nil]
    }
}

@MainActor
private final class LocalAccountRecoveryFixture: ObservableObject {
    enum Scenario: String { case nilConfiguration, genericSeal, corrupt, configured, accountRoundTrip, localFavorites, localFavoritesFailure, localResume, localResumeFailure, localPodcast, localPodcastFailure, localIntroduction, localIntroductionFailure, localHistory, localHistoryFailure, pushInstallation, pushMissingACK, pushChangedBinding, pushTimeout, pushRestart, pushRestartChangedACK }
    private final class User { let uid: String; init(_ uid: String) { self.uid = uid } }
    let scenario: Scenario
    let auth: AuthService
    let recovery: ReaderTransitionRecovery
    let startup: ReaderSDKStartupState
    let root: URL
    let configuration: ReaderDeletionHTTPTransport.Configuration
    let google = GoogleSignInService(reauthenticationProvider: { _, _ in throw CancellationError() })
    @Published private(set) var ready = false
    private var preparing = false
    private var user = User("local-reader-A")
    private let now: Int64 = 1_800_000_000_123
    private var delegate: AppDelegate?
    private var subscriptions: Set<AnyCancellable> = []
    private var publicationScheduled = false
    private var publicationNeedsRefresh = false
    private var factoryCalls = 0, sdkCalls = 0, httpCalls = 0, readerEffects = 0, preferenceEffects = 0
    private var heldHTTP: CheckedContinuation<Void, Never>?
    private var sentScopes: [String] = [], sentIDs: [String] = [], actionIDs: [UUID] = []
    private var observedCoordinators: Set<ObjectIdentifier> = []
    private var armedRoundTrip = false
    private var roundTrips = 0
    private let pushStorage: LocalRecoveryPushStorage
    private let reconstructionCount: Int
    private lazy var pushVault = PushInstallationVault(store: pushStorage, makeIdentity: { throw CancellationError() })
    private var pushDeadline: (id: UUID, action: @MainActor () -> Void)?
    private var pushPreparationCalls = 0, pushCommitCalls = 0, pushRemoteCommits = 0
    private var pushCommitDigests: [String] = []
    private var pushCommitIDs: [String] = []
    private var acceptedPushCommitDigest: String?
    private var localEvidence = LocalRecoveryFavoritesDisk.Evidence()
    private var resumeEvidence = LocalRecoveryResumeDisk.Evidence()
    private let podcastStorage = LocalRecoveryPodcastStorage()
    private var podcastRuntime: PodcastProgressRuntime?
    private let introductionStorage = LocalRecoveryIntroductionStorage()
    private var introductionModel: ReaderIntroductionModel?
    private let historyStorage = LocalRecoveryHistoryStorage()
    private var historyRuntime: ReadingHistoryRuntime?
    private var historyOriginalTicket: ReadingHistoryModel.ArticleTicket?
    private var historyProbedStatuses: Set<String> = []
    private lazy var resumeDisk = LocalRecoveryResumeDisk(file: root.appendingPathComponent("reader-resume.json"))
    private lazy var resumeStore: ReaderResumeStore = {
        let disk = resumeDisk
        disk.onChange { [weak self] in Task { @MainActor [weak self] in self?.schedulePublication() } }
        return ReaderResumeStore(storage: .init(read: { try disk.read() }, write: { try disk.write($0) }))
    }()
    private var journalFactoryCalls = 0
    private var localJournal: FavoritesFileJournal?
    private var retainedFavoritesDisk: LocalRecoveryFavoritesDisk?
    private lazy var favoritesDisk = retainedFavoritesDisk ?? LocalRecoveryFavoritesDisk(directory: root.appendingPathComponent("favorites"),
        owner: FavoritesContext.confirmed(userID: "local-reader-A").namespace!)
    var usesPush: Bool { [.pushInstallation, .pushMissingACK, .pushChangedBinding, .pushTimeout, .pushRestart, .pushRestartChangedACK].contains(scenario) }
    var usesPushReconstruction: Bool { scenario == .pushRestart || scenario == .pushRestartChangedACK }
    var usesLocalHistory: Bool { scenario == .localHistory || scenario == .localHistoryFailure }
    var usesLocalIntroduction: Bool { scenario == .localIntroduction || scenario == .localIntroductionFailure || usesLocalHistory }
    var usesLocalPodcast: Bool { scenario == .localPodcast || scenario == .localPodcastFailure || usesLocalIntroduction }
    var usesLocalResume: Bool { scenario == .localResume || scenario == .localResumeFailure || usesLocalPodcast }
    var usesLocalFavorites: Bool { scenario == .localFavorites || scenario == .localFavoritesFailure || usesLocalResume || usesPush }
    lazy var preferences = ReaderPreferencesModel(capturePermission: { { false } }, identity: { [unowned self] in
        .init(actualUID: user.uid, canonicalUID: auth.state.snapshot.userID)
    }, load: { [unowned self] _, _ in preferenceEffects += 1; throw CancellationError() },
       save: { [unowned self] _, _ in preferenceEffects += 1; throw CancellationError() }, schedule: { _ in {} })
    lazy var actions = ReaderAccountActions(canonical: auth.state, preferences: preferences,
        verify: { _ in }, refresh: { _ in throw CancellationError() })
    private lazy var operations = AuthOperationCoordinator(canonical: auth.state,
        actualUserID: { [unowned self] in user.uid }, reauthenticationIdentity: auth.bootstrapIdentity)
    private lazy var reauthentication = ReaderAccountReauthentication<String>(canonical: auth.bootstrapIdentity,
        operations: operations, captureUser: { [unowned self] in
            let original = user
            return .init(uid: original.uid, isCurrent: { [unowned self] in user === original },
                reauthenticate: { [unowned self] _, current in
                    guard current() else { throw CancellationError() }
                    sdkCalls += 1
                    // The actual coordinator must reread the original selection
                    // after fresh reauthentication, before any commit request.
                    if scenario == .pushChangedBinding && sdkCalls == 4 {
                        try pushStorage.replaceWithOtherAccount(appID: configuration.appID)
                    }
                    schedulePublication()
                    return .init(uid: original.uid, authTimeMs: (now / 1_000) * 1_000)
                }, deletionCredentials: { [unowned self] proof, current in
                    guard current() else { throw CancellationError() }
                    actionIDs.append(proof.action.actionID)
                    return .init(ownerUID: original.uid, projectID: configuration.projectID, appID: configuration.appID,
                        idToken: "local.id." + proof.action.actionID.uuidString,
                        appCheckToken: "local.app." + proof.action.actionID.uuidString,
                        authTimeMs: proof.authTimeMs, authValidUntilMs: now + 60_000, appCheckValidUntilMs: now + 60_000)
                }, email: "original.reader@example.invalid", supportsPassword: true)
        }, nowMilliseconds: { [unowned self] in now })

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-AccountRecoveryScenario"), arguments.indices.contains(index + 1) {
            scenario = Scenario(rawValue: arguments[index + 1]) ?? .nilConfiguration
        } else { scenario = .nilConfiguration }
        pushStorage = LocalRecoveryPushStorage(); reconstructionCount = 0
        root = FileManager.default.temporaryDirectory.appendingPathComponent("local-account-recovery-" + UUID().uuidString)
        let localRecovery = ReaderTransitionRecovery(store: .init(rootDirectory: root))
        recovery = localRecovery
        let localStartup = ReaderSDKStartupState(legacyRecovery: localRecovery)
        startup = localStartup; auth = AuthService(startup: localStartup)
        configuration = try! .init(projectID: "local-deletion", appID: "1:123456789:ios:abcdef123456",
            endpointURL: URL(string: "https://reauth.example.invalid/reader")!)
        auth.objectWillChange.sink { [weak self] in self?.schedulePublication() }.store(in: &subscriptions)
    }
    /// Logical reconstruction only: the new object owns a new Auth, startup,
    /// recovery store/runtime, operations, provider prompt, and coordinator.
    /// The isolated file bytes and fake remote state survive; this is not a
    /// terminated process, live Keychain, or remote service durability test.
    private init(reconstructing previous: LocalAccountRecoveryFixture) {
        scenario = previous.scenario; root = previous.root; configuration = previous.configuration
        pushStorage = previous.pushStorage; reconstructionCount = previous.reconstructionCount + 1
        let localRecovery = ReaderTransitionRecovery(store: .init(rootDirectory: root))
        recovery = localRecovery
        let localStartup = ReaderSDKStartupState(legacyRecovery: localRecovery)
        startup = localStartup; auth = AuthService(startup: localStartup)
        factoryCalls = previous.factoryCalls; sdkCalls = previous.sdkCalls; httpCalls = previous.httpCalls
        readerEffects = previous.readerEffects; preferenceEffects = previous.preferenceEffects
        sentScopes = previous.sentScopes; sentIDs = previous.sentIDs; actionIDs = previous.actionIDs
        pushPreparationCalls = previous.pushPreparationCalls; pushCommitCalls = previous.pushCommitCalls
        pushRemoteCommits = previous.pushRemoteCommits; pushCommitDigests = previous.pushCommitDigests
        pushCommitIDs = previous.pushCommitIDs; acceptedPushCommitDigest = previous.acceptedPushCommitDigest
        localEvidence = previous.localEvidence
        // Preserve the original B/guest byte expectations, not an empty
        // freshly constructed checker that would vacuously accept changes.
        retainedFavoritesDisk = previous.favoritesDisk
        auth.objectWillChange.sink { [weak self] in self?.schedulePublication() }.store(in: &subscriptions)
    }
    var canReconstruct: Bool {
        usesPushReconstruction && reconstructionCount == 0 && ready && heldHTTP == nil
            && auth.accountRecoveryFlow?.coordinator.pushStatus == .timedOut
            && auth.accountRecoveryFlow?.coordinator.hasPhysicalFlight == false
    }
    func reconstruct() -> LocalAccountRecoveryFixture? {
        guard canReconstruct else { return nil }
        do {
            if scenario == .pushRestartChangedACK { try pushStorage.replaceWithOtherAccount(appID: configuration.appID) }
            if let flow = auth.accountRecoveryFlow { auth.cancelAccountRecovery(flow) }
            return LocalAccountRecoveryFixture(reconstructing: self)
        } catch { return nil }
    }
    var activeConfiguration: ReaderDeletionHTTPTransport.Configuration? {
        scenario == .nilConfiguration ? nil : configuration
    }
    func prepare() async {
        guard !preparing else { return }; preparing = true
        do {
            if reconstructionCount > 0 {
                // Bootstrap rereads the retained files; neither seed() nor
                // vault.prepare is used to manufacture recovery evidence.
                let disk = favoritesDisk
                localEvidence = await Task.detached(priority: .utility) { disk.evidence() }.value
                await runOriginalStartup()
                guard !Task.isCancelled else { return }
                ready = true
                return
            }
            if usesPush { try pushStorage.seed(appID: configuration.appID, acknowledged: scenario != .pushMissingACK) }
            if usesLocalFavorites {
                let other = FavoritesContext.confirmed(userID: "local-reader-B").namespace!
                let records = try [favoritesDisk.owner, other, .guest].enumerated().map { index, namespace in
                    let article = Article(id: "local-favorite-\(index)", name: "Gemte valg", slug: "local-favorite-\(index)",
                        content: "", intro: "", topicID: "local-topic", contentRevision: "local-r1")
                    let metadata = try JSONSerialization.jsonObject(with: JSONEncoder().encode([FavoritesRecord.Metadata(article)]))
                    let legacy = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1,
                        "namespace": namespace.recordBinding, "entries": metadata])
                    return (namespace, legacy, try FavoritesRecordCodec.encode(.init(articles: [article]), namespace: namespace))
                }
                let disk = favoritesDisk
                disk.configureFailure(scenario == .localFavoritesFailure)
                try await Task.detached(priority: .utility) { try disk.seed(records) }.value
                localEvidence = await Task.detached(priority: .utility) { disk.evidence() }.value
            }
            if usesLocalResume {
                let disk = resumeDisk, failReadback = scenario == .localResumeFailure
                try await Task.detached(priority: .utility) { try disk.seed(failReadback: failReadback) }.value
                resumeEvidence = await Task.detached(priority: .utility) { disk.evidence() }.value
            }
            if usesLocalPodcast {
                try podcastStorage.seed(failReadback: scenario == .localPodcastFailure)
                podcastRuntime = PodcastProgressRuntime(disabled: false,
                    storageFactory: { [unowned self] in self.podcastStorage.storage }, recovery: recovery)
            }
            if usesLocalIntroduction {
                try introductionStorage.seed(failReadback: scenario == .localIntroductionFailure)
                introductionModel = ReaderIntroductionModel(storage: introductionStorage.storage, recovery: recovery)
            }
            if usesLocalHistory {
                try historyStorage.seed(failReadback: scenario == .localHistoryFailure)
                // A real original timer and observer are created only against
                // injected memory effects before the same recovery is sealed.
                try await recovery.bootstrap()
                let memory = historyStorage
                let runtime = ReadingHistoryRuntime(disabled: false, transportFactory: {
                    memory.factoryCalls += 1
                    return .init(storage: memory.storage, observe: { callback in
                        memory.callbacks.append(callback); return {}
                    }, synchronize: { memory.synchronizations += 1 })
                }, schedule: { _, action in memory.timers.append(action); return {} },
                    markProfileRead: { _, _ in memory.profileWrites += 1 }, recovery: recovery,
                    cleanupStorage: memory.cleanupCapability)
                historyRuntime = runtime
                runtime.prepareIfNeeded(); runtime.changeAccountContext(userID: "local-reader-A")
                guard let ticket = runtime.model.beginArticle(articleID: "local-history-0-0"),
                      runtime.model.saveProgress(0.4, ticket: ticket) == .scheduled else { throw CancellationError() }
                historyOriginalTicket = ticket
            }
            let seed = ReaderTransitionRecovery(store: .init(rootDirectory: root))
            try await seed.bootstrap()
            _ = try await seed.seal(binding: .init(ownerUID: "local-reader-A", epoch: 7))
            if scenario != .genericSeal {
                let request = try ReaderAccountDeletionContract.Request(expectedUID: "local-reader-A", membershipEpoch: 7)
                let digest = ReaderTransitionRecoveryStore.deletionConfigurationDigest(projectID: configuration.projectID,
                    appID: configuration.appID, endpoint: configuration.endpointURL)
                _ = try await seed.recordDeletion(request: request, phase: .parent, configurationDigest: digest)
                if scenario == .corrupt {
                    let file = root.appendingPathComponent("reader-deletion-v1.json")
                    try await Task.detached(priority: .utility) { try Data("invalid local checkpoint".utf8).write(to: file, options: .atomic) }.value
                }
            }
            await runOriginalStartup()
            guard !Task.isCancelled else { return }
            if let runtime = historyRuntime, let ticket = historyOriginalTicket {
                historyStorage.exerciseOldCallbacks(runtime: runtime, ticket: ticket)
                historyStorage.resetSourceCountersAfterOriginalSetup()
            }
            ready = true
        } catch { ready = true }
    }
    private func runOriginalStartup() async {
        let localDelegate = AppDelegate(startup: startup, identity: auth.bootstrapIdentity,
            actualUserID: { [unowned self] in user.uid })
        delegate = localDelegate
        if let task = localDelegate.runAccountStartup(authOnly: {},
            readerSteps: [{ [unowned self] in readerEffects += 1 }],
            observeAuth: { [unowned self] in observe("local-reader-A") },
            releaseReader: { [unowned self] in _ = auth.resumeReaderAfterLocalRecovery() }) {
            await task.value
        }
    }
    private func observe(_ uid: String) {
        if user.uid != uid { user = User(uid) }
        let session = ReaderAccountSession(uid: uid, email: "local@example.invalid", isEmailVerified: true)
        _ = auth.observeIdentity(session, currentUserID: { [unowned self] in user.uid },
            revokeReader: { [unowned self] current in auth.state.suspend(stillPermitted: current) != nil },
            publishReader: { [unowned self] current in
                readerEffects += 1; return auth.state.adopt(session, stillPermitted: current)
            })
    }
    var supportedProviders: @MainActor (AuthService.RecoveryTicket) -> Set<AuthService.RecoveryProvider> {
        { [unowned self] ticket in reauthentication.supportedMethods(context: ticket.context) }
    }
    var factory: AuthService.RecoveryFactory {
        { [unowned self] provider, prompts in
            factoryCalls += 1
            guard provider == .email else { schedulePublication(); return nil }
            let localFactory: (@MainActor () -> FavoritesFileJournal?)?
            if usesLocalFavorites { localFactory = { [unowned self] in self.makeLocalJournal() } }
            else { localFactory = nil }
            let coordinator = auth.makeEmailReaderAccountDeletion(configuration: configuration,
                reauthentication: reauthentication, prompt: prompts.email,
                makeCredential: { _, password in password },
                execute: { [unowned self] request in try await execute(request) },
                now: { [unowned self] in now }, scheduleTimeout: { [unowned self] _, action in
                    guard usesPush else { return {} }
                    let id = UUID(); pushDeadline = (id, action)
                    return { [weak self] in
                        if self?.pushDeadline?.id == id { self?.pushDeadline = nil }
                        self?.schedulePublication()
                    }
                }, resumingAfterRestart: true,
                localJournalFactory: localFactory, localResumeStore: usesLocalResume ? resumeStore : nil,
                localPodcastStore: usesLocalPodcast ? podcastRuntime?.localCleanupStore() : nil,
                localIntroductionModel: introductionModel, localHistoryModel: historyRuntime?.localCleanupModel(),
                pushInstallationVault: usesPush ? pushVault : nil)
            if let coordinator, observedCoordinators.insert(ObjectIdentifier(coordinator)).inserted {
                coordinator.objectWillChange.sink { [weak self] in self?.schedulePublication() }.store(in: &subscriptions)
            }
            schedulePublication()
            return coordinator
        }
    }
    private func makeLocalJournal() -> FavoritesFileJournal? {
        journalFactoryCalls += 1
        if let localJournal { return localJournal }
        let disk = favoritesDisk
        disk.onChange { [weak self] in Task { @MainActor [weak self] in self?.schedulePublication() } }
        let value = FavoritesFileJournal(rootDirectory: disk.directory,
            legacyRead: { try disk.legacyRead($0) }, legacyAdmission: recovery.admission,
            legacyDelete: { try disk.legacyDelete($0, expected: $1) }, remove: { try disk.remove($0) })
        localJournal = value
        return value
    }
    func releaseLocalRemoval() { favoritesDisk.releaseRemove(); schedulePublication() }
    func releaseResumeWrite() { resumeDisk.releaseWrite(); schedulePublication() }
    private func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let bytes = request.httpBody, let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let uid = object["expectedUID"] as? String, let epoch = object["membershipEpoch"] as? Int64,
              let url = request.url else { throw URLError(.cannotParseResponse) }
        if let scope = object["scope"] as? String,
           [ReaderAccountDeletionContract.pushPreparationScope, ReaderAccountDeletionContract.pushScope].contains(scope) {
            return try await executePush(request, bytes: bytes, url: url)
        }
        let parent = try ReaderAccountDeletionContract.Request(expectedUID: uid, membershipEpoch: epoch)
        let ledger = object["scope"] as? String == ReaderAccountDeletionContract.ledgerScope
        httpCalls += 1; let attempt = httpCalls
        sentScopes.append(ledger ? "ledger" : "parent"); sentIDs.append(parent.requestID)
        await withCheckedContinuation { heldHTTP = $0; schedulePublication() }
        if scenario == .configured && attempt == 1 { throw URLError(.timedOut) }
        var result: [String: Any] = ["requestID": parent.requestID, "scope": ReaderAccountDeletionContract.scope,
            "status": "scopedCloudDataRemoved", "accountDeletionComplete": false,
            "unresolved": ReaderAccountDeletionContract.unresolved, "removedFavoriteDocuments": 0]
        if ledger {
            guard let parentID = object["parentRequestID"] as? String else { throw URLError(.cannotParseResponse) }
            let child = try ReaderAccountDeletionContract.LedgerRequest(expectedUID: uid, membershipEpoch: epoch,
                parentRequestID: parentID)
            result = ["requestID": child.requestID, "parentRequestID": parentID,
                "scope": ReaderAccountDeletionContract.ledgerScope, "status": "ledgerDataRemoved",
                "accountDeletionComplete": false, "unresolved": ReaderAccountDeletionContract.ledgerUnresolved,
                "removedReceiptDocuments": 0, "removedRevisionDocuments": 0]
        }
        return (try JSONSerialization.data(withJSONObject: result), HTTPURLResponse(url: url, statusCode: 200,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!)
    }
    private func executePush(_ request: URLRequest, bytes: Data, url: URL) async throws -> (Data, HTTPURLResponse) {
        typealias Contract = ReaderAccountDeletionContract
        let original = try JSONDecoder().decode(Contract.PushRequest.self, from: bytes)
        let installation = original.installation
        guard original.expectedUID == "local-reader-A", original.membershipEpoch == 7,
              installation.installationId == LocalRecoveryPushStorage.installationID,
              installation.expected.ownerEpoch == 4, installation.expected.revision == 9,
              installation.expected.clientRevision == 17 else { throw URLError(.cannotParseResponse) }
        let preparing = original.scope == Contract.pushPreparationScope
        httpCalls += 1; sentScopes.append(preparing ? "pushPrepare" : "pushCommit"); sentIDs.append(original.requestID)
        if preparing { pushPreparationCalls += 1 }
        else {
            pushCommitCalls += 1; pushCommitDigests.append(PushRegistrationValidation.hash(bytes))
            pushCommitIDs.append(original.requestID)
        }
        await withCheckedContinuation { heldHTTP = $0; schedulePublication() }
        let result: [String: Any]
        if preparing {
            let snapshot = try Contract.PushSnapshot(requestId: installation.requestId,
                installationId: installation.installationId, appId: configuration.appID, ownerUID: original.expectedUID,
                ownerEpoch: installation.expected.ownerEpoch, revision: installation.expected.revision,
                clientRevision: installation.expected.clientRevision, stateDigest: String(repeating: "e", count: 64))
            result = ["schemaVersion": 1, "scope": Contract.pushPreparationScope,
                "expectedUID": original.expectedUID, "membershipEpoch": original.membershipEpoch,
                "parentRequestID": original.parentRequestID, "ledgerRequestID": original.ledgerRequestID,
                "installationId": installation.installationId, "status": "prepared", "preparedOnly": true,
                "retirementComplete": false, "accountDeletionComplete": false, "historicalMaterialComplete": false,
                "deliveriesRecalled": false, "unresolved": Contract.pushUnresolved,
                "snapshot": try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot))]
        } else {
            let digest = PushRegistrationValidation.hash(bytes)
            if let acceptedPushCommitDigest {
                guard acceptedPushCommitDigest == digest else { throw URLError(.cannotParseResponse) }
            } else { acceptedPushCommitDigest = digest; pushRemoteCommits += 1 }
            let child: [String: Any] = ["schemaVersion": 1, "status": "retired", "requestId": installation.requestId,
                "installationId": installation.installationId, "ownerUID": original.expectedUID, "appId": configuration.appID,
                "ownerEpoch": installation.expected.ownerEpoch, "revision": installation.expected.revision + 1,
                "clientRevision": installation.expected.clientRevision, "retiredAtMs": now,
                "retiredChallenges": 1, "removedTokenOwners": 1, "preservedForeignChallenges": 0,
                "preservedForeignTokenOwners": 0, "preservedUnprovenTokenOwners": 0,
                "accountDeletionComplete": false, "historicalMaterialComplete": false, "deliveriesRecalled": false]
            result = ["requestID": original.requestID, "scope": Contract.pushScope,
                "parentRequestID": original.parentRequestID, "ledgerRequestID": original.ledgerRequestID,
                "installationId": installation.installationId, "status": "installationRetired",
                "accountDeletionComplete": false, "historicalMaterialComplete": false, "deliveriesRecalled": false,
                "unresolved": Contract.pushUnresolved, "retirementReceipt": child]
        }
        return (try JSONSerialization.data(withJSONObject: result), HTTPURLResponse(url: url, statusCode: 200,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!)
    }
    func firePushTimeout() {
        guard auth.accountRecoveryFlow?.coordinator.pushStatus == .retiring, heldHTTP != nil else { return }
        pushDeadline?.action(); schedulePublication()
    }
    func releaseHTTP() { let old = heldHTTP; heldHTTP = nil; old?.resume(); schedulePublication() }
    func armRoundTrip() { armedRoundTrip = true; schedulePublication() }
    func becameActive() {
        guard armedRoundTrip else { return }; armedRoundTrip = false
        observe("local-reader-B"); observe("local-reader-A"); roundTrips += 1; schedulePublication()
    }
    private func schedulePublication() {
        guard !publicationScheduled else { publicationNeedsRefresh = true; return }
        publicationScheduled = true; publicationNeedsRefresh = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.usesLocalFavorites {
                let disk = self.favoritesDisk
                let evidence = await Task.detached(priority: .utility) { disk.evidence() }.value
                if self.usesLocalResume {
                    let resumeDisk = self.resumeDisk
                    let resumeEvidence = await Task.detached(priority: .utility) { resumeDisk.evidence() }.value
                    self.objectWillChange.send()
                    self.resumeEvidence = resumeEvidence
                } else { self.objectWillChange.send() }
                self.localEvidence = evidence
            } else { self.objectWillChange.send() }
            if let runtime = self.historyRuntime, let ticket = self.historyOriginalTicket,
               let coordinator = self.auth.accountRecoveryFlow?.coordinator {
                let status = String(describing: coordinator.localHistoryStatus)
                if (status == "failed" || status == "removed"), self.historyProbedStatuses.insert(status).inserted {
                    self.historyStorage.exerciseOldCallbacks(runtime: runtime, ticket: ticket)
                }
            }
            self.publicationScheduled = false
            // A completion can arrive during either detached evidence read.
            // Coalesce it into a fresh task after publication, not into the
            // synchronous objectWillChange callback or SwiftUI rendering.
            if self.publicationNeedsRefresh { self.schedulePublication() }
        }
    }
    var report: String {
        let flow = auth.accountRecoveryFlow
        var values: [String: Any] = ["ready": ready, "firebaseStarted": FirebaseApp.allApps != nil,
            "readerUnresolved": auth.state.snapshot.context == .unresolved,
            "bootstrapUID": auth.bootstrapIdentity.snapshot.session?.uid ?? "",
            "factoryCalls": factoryCalls, "sdkCalls": sdkCalls, "httpCalls": httpCalls,
            "readerEffects": readerEffects, "preferenceEffects": preferenceEffects,
            "flowID": flow?.id.uuidString ?? "", "status": flow.map { String(describing: $0.coordinator.status) } ?? "none",
            "physicalFlight": flow?.coordinator.hasPhysicalFlight ?? false, "httpHeld": heldHTTP != nil,
            "promptID": flow?.prompts.email.presentation?.id.uuidString ?? "",
            "sentScopes": sentScopes, "sentIDs": sentIDs, "actionIDs": actionIDs.map(\.uuidString),
            "complete": flow?.coordinator.accountDeletionComplete ?? false,
            "armed": armedRoundTrip, "roundTrips": roundTrips,
            "localStatus": flow.map { String(describing: $0.coordinator.localFavoritesStatus) } ?? "none",
            "localConfirmation": flow?.coordinator.localFavoritesConfirmation != nil,
            "localJournalFactoryCalls": journalFactoryCalls,
            "localRemoveHeld": usesLocalFavorites && favoritesDisk.isHeld,
            "localRemoveStarts": usesLocalFavorites ? favoritesDisk.removeStarts : 0,
            "ownV1": localEvidence.ownV1, "ownV2": localEvidence.ownV2,
            "otherUnchanged": localEvidence.otherUnchanged, "guestUnchanged": localEvidence.guestUnchanged,
            "recoveryClosed": !recovery.admission.isAllowed,
            "resumeStatus": flow.map { String(describing: $0.coordinator.localResumeStatus) } ?? "none",
            "resumeConfirmation": flow?.coordinator.localResumeConfirmation != nil,
            "resumeWriteHeld": usesLocalResume && resumeDisk.isHeld,
            "resumeWriteStarts": usesLocalResume ? resumeDisk.writeStarts : 0,
            "resumeReadFailures": usesLocalResume ? resumeDisk.failureCount : 0,
            "resumeOwnerCount": resumeEvidence.ownerCount,
            "resumeOtherUnchanged": resumeEvidence.otherUnchanged,
            "resumeGuestUnchanged": resumeEvidence.guestUnchanged]
        if usesPush {
            values.merge(pushStorage.evidence) { _, new in new }
            values["pushStatus"] = flow.map { String(describing: $0.coordinator.pushStatus) } ?? "none"
            values["pushConfirmation"] = flow?.coordinator.pushConfirmation != nil
            values["pushReceipt"] = flow?.coordinator.pushReceipt != nil
            values["pushCanPrepare"] = flow?.coordinator.canPreparePushRetirement ?? false
            values["pushCanRetry"] = flow?.coordinator.canRetryPushRetirement ?? false
            values["pushPreparationCalls"] = pushPreparationCalls
            values["pushCommitCalls"] = pushCommitCalls
            values["pushRemoteCommits"] = pushRemoteCommits
            values["pushCommitDigests"] = pushCommitDigests
            values["pushCommitIDs"] = pushCommitIDs
            values["pushStoredCommit"] = flow?.coordinator.hasStoredPushCommit ?? false
            values["pushReconstructionCount"] = reconstructionCount
            values["pushCanReconstruct"] = canReconstruct
            values["pushHistoricalComplete"] = flow?.coordinator.pushReceipt?.historicalMaterialComplete ?? false
            values["pushDeliveriesRecalled"] = flow?.coordinator.pushReceipt?.deliveriesRecalled ?? false
        }
        if usesLocalPodcast {
            values["podcastStatus"] = flow.map { String(describing: $0.coordinator.localPodcastStatus) } ?? "none"
            values["podcastConfirmation"] = flow?.coordinator.localPodcastConfirmation != nil
            values["podcastFactoryCalls"] = podcastStorage.factoryCalls
            values["podcastReads"] = podcastStorage.reads
            values["podcastWrites"] = podcastStorage.writes
            values["podcastRemovalWrites"] = podcastStorage.removalWrites
            values["podcastReadFailures"] = podcastStorage.readFailures
            values["podcastOwnerCount"] = podcastStorage.ownerCount
            values["podcastOtherUnchanged"] = podcastStorage.otherUnchanged
            values["podcastGuestUnchanged"] = podcastStorage.guestUnchanged
            values["podcastLegacyUnchanged"] = podcastStorage.legacyUnchanged
            values["podcastPlaybackAccess"] = podcastRuntime?.model.hasPlaybackAccess ?? false
        }
        if usesLocalIntroduction {
            values["introductionStatus"] = flow.map { String(describing: $0.coordinator.localIntroductionStatus) } ?? "none"
            values["introductionConfirmation"] = flow?.coordinator.localIntroductionConfirmation != nil
            values["introductionReads"] = introductionStorage.reads
            values["introductionWrites"] = introductionStorage.writes
            values["introductionCleanupReads"] = introductionStorage.cleanupReads
            values["introductionCleanupWrites"] = introductionStorage.cleanupWrites
            values["introductionClearWrites"] = introductionStorage.clearWrites
            values["introductionReadFailures"] = introductionStorage.readFailures
            values["introductionTopicCount"] = introductionStorage.topicCount
            values["introductionCompleted"] = introductionStorage.completed
            values["introductionReplaying"] = introductionStorage.replaying
            values["introductionStep"] = introductionStorage.step
            values["introductionOwnerCleared"] = introductionStorage.ownerCleared
            values["introductionGuestUnchanged"] = introductionStorage.guestUnchanged
            values["introductionAllowed"] = introductionModel?.permitsIntroduction ?? false
            values["introductionPresented"] = introductionModel?.isPresented ?? false
        }
        if usesLocalHistory {
            values["historyStatus"] = flow.map { String(describing: $0.coordinator.localHistoryStatus) } ?? "none"
            values["historyConfirmation"] = flow?.coordinator.localHistoryConfirmation != nil
            values["historyLocalReadback"] = flow?.coordinator.localHistoryReceipt?.isLocalReadbackConfirmed ?? false
            values["historyCloudComplete"] = flow?.coordinator.localHistoryReceipt?.cloudCleanupComplete ?? false
            values["historyReads"] = historyStorage.reads
            values["historyWrites"] = historyStorage.writes
            values["historyMetadataReads"] = historyStorage.metadataReads
            values["historyMetadataWrites"] = historyStorage.metadataWrites
            values["historyRemovalWrites"] = historyStorage.removalWrites
            values["historyReadFailures"] = historyStorage.readFailures
            values["historyOwnerCount"] = historyStorage.ownerCount
            values["historyOtherUnchanged"] = historyStorage.otherUnchanged
            values["historyGuestUnchanged"] = historyStorage.guestUnchanged
            values["historyLegacyUnchanged"] = historyStorage.legacyUnchanged
            values["historyFactoryCalls"] = historyStorage.factoryCalls
            values["historySynchronizations"] = historyStorage.synchronizations
            values["historyProfileWrites"] = historyStorage.profileWrites
            values["historyTimers"] = historyStorage.timers.count
            values["historyObservers"] = historyStorage.callbacks.count
            values["historyStaleProbes"] = historyStorage.staleProbeCount
            values["historyStaleEffectsDenied"] = historyStorage.staleEffectsDenied
            values["historyContextUnresolved"] = historyRuntime?.model.context == .unresolved
        }
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }; return text
    }
}

@MainActor
private final class LocalAccountRecoveryFixtureHost: ObservableObject {
    @Published private(set) var fixture = LocalAccountRecoveryFixture()
    func reconstruct() {
        guard let replacement = fixture.reconstruct() else { return }
        fixture = replacement
    }
}

struct LocalAccountRecoverySmokeView: View {
    @StateObject private var host = LocalAccountRecoveryFixtureHost()
    var body: some View {
        LocalAccountRecoveryFixtureView(fixture: host.fixture, reconstruct: host.reconstruct)
            .id(ObjectIdentifier(host.fixture))
    }
}

private struct LocalAccountRecoveryFixtureView: View {
    @ObservedObject var fixture: LocalAccountRecoveryFixture
    var reconstruct: () -> Void
    @State private var showAccount = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase er startet")
                        .accessibilityIdentifier("accountRecovery.firebase")
                    Button("Åbn konto") { showAccount = true }
                        .disabled(!fixture.ready).accessibilityIdentifier("accountRecovery.open")
                }
                // Keep one interactive diagnostics panel. The Auth/flow owner
                // remains mounted while its account sheet is presented.
                if !showAccount { controls(identifier: "accountRecovery.backgroundControls") }
            }
            .navigationTitle("Lokal kontogendannelse")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.primary)
        }
        .sheet(isPresented: $showAccount) {
            NavigationStack {
                ReaderAccountSheetContent(canonical: fixture.auth.state, preferences: fixture.preferences,
                    actions: fixture.actions, topics: [], onDone: { showAccount = false }, newsletter: { _ in AnyView(EmptyView()) },
                    recoveryContent: { AnyView(ReaderAccountRecoverySection(auth: fixture.auth,
                        configuration: fixture.activeConfiguration, googleService: fixture.google, factory: fixture.factory,
                        supportedProviders: fixture.supportedProviders)) },
                    recoveryPresentation: { AnyView(ReaderAccountRecoveryPresentation(auth: fixture.auth)) }) {
                        Section { Text("Uventet gæsteindhold").accessibilityIdentifier("accountRecovery.guest") }
                    } extraContent: { EmptyView() }
                    .toolbar { ToolbarItem(placement: .cancellationAction) {
                        Button("Luk") { showAccount = false }.accessibilityIdentifier("accountRecovery.close")
                    } }
                    .safeAreaInset(edge: .bottom) { controls(identifier: "accountRecovery.controls").padding(8).background(.regularMaterial).dynamicTypeSize(.small ... .medium) }
                    .tint(.primary)
            }
        }
        .task { await fixture.prepare() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { fixture.becameActive() } }
    }
    private func controls(identifier: String) -> some View {
        VStack(spacing: 4) {
            Button("Frigiv lokalt HTTP-svar") { fixture.releaseHTTP() }
                .accessibilityIdentifier("accountRecovery.releaseHTTP")
            if fixture.scenario == .pushTimeout || fixture.usesPushReconstruction {
                Button("Udløs lokal pushfrist") { fixture.firePushTimeout() }
                    .accessibilityIdentifier("accountRecovery.pushTimeout")
            }
            if fixture.usesPushReconstruction {
                Button("Genskab lokale kontoobjekter") { reconstruct() }
                    .disabled(!fixture.canReconstruct)
                    .accessibilityIdentifier("accountRecovery.reconstruct")
            }
            if fixture.usesLocalFavorites && !fixture.usesPush {
                Button("Frigiv lokal filfjernelse") { fixture.releaseLocalRemoval() }
                    .accessibilityIdentifier("accountRecovery.releaseLocal")
            }
            if fixture.usesLocalResume {
                Button("Frigiv lokal positionsskrivning") { fixture.releaseResumeWrite() }
                    .accessibilityIdentifier("accountRecovery.releaseResume")
            }
            if fixture.scenario == .accountRoundTrip {
                Button("Kontoskift ved næste forgrund") { fixture.armRoundTrip() }
                    .accessibilityIdentifier("accountRecovery.armRoundTrip")
            }
            Text("Lokal teststatus").font(.caption)
                .accessibilityIdentifier("accountRecovery.report").accessibilityValue(fixture.report)
        }
        .font(.footnote).tint(.primary)
        .accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
    }
}
#endif
