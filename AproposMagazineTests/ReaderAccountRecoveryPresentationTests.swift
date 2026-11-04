import Combine
import FirebaseCore
import XCTest
@testable import Apropos

/// Auth's actual recovery projection and explicit action seam, backed by a cold
/// startup and real isolated checkpoint files. Providers, SDK and HTTP are local.
@MainActor
final class ReaderAccountRecoveryPresentationTests: XCTestCase {
    private typealias Model = ReaderAccountDeletionCoordinator
    private typealias Contract = ReaderAccountDeletionContract
    private typealias Bridge = ReaderAccountReauthentication<String>
    private typealias Flow = AuthService.RecoveryFlow
    private typealias Ticket = AuthService.RecoveryTicket
    private enum Records: Equatable { case marker, checkpoint, corrupt }
    private enum Failure: Error { case read, timeout, malformed }
    @MainActor private final class User {
        let uid: String
        var supportsPassword = true
        init(_ uid: String) { self.uid = uid }
    }
    @MainActor private final class Gate {
        var entered = false
        private var wait: CheckedContinuation<Void, Never>?
        func hold() async { await withCheckedContinuation { wait = $0; entered = true } }
        func release() { let old = wait; wait = nil; old?.resume() }
    }
    private final class ReadControl: @unchecked Sendable {
        private let lock = NSLock(), semaphore = DispatchSemaphore(value: 0)
        private var reads = 0, held = false, fails = false
        private var readHook: (@Sendable () -> Void)?
        func setHook(_ hook: (@Sendable () -> Void)?) { lock.withLock { readHook = hook } }
        var count: Int { lock.lock(); defer { lock.unlock() }; return reads }
        func holdNext() { lock.lock(); held = true; lock.unlock() }
        func failNext() { lock.lock(); fails = true; lock.unlock() }
        func release() { semaphore.signal() }
        func read() throws {
            lock.lock(); reads += 1; let hold = held, fail = fails, hook = readHook; held = false; fails = false; lock.unlock()
            hook?()
            if hold, semaphore.wait(timeout: .now() + 5) != .success { throw Failure.timeout }
            if fail { throw Failure.read }
        }
    }
    /// Injectable physical effects used by the actual journal. Test controls do
    /// not release a physical operation when the logical action is cancelled.
    private final class LocalDisk: @unchecked Sendable {
        enum Point { case read, pending, remove }
        private let lock = NSLock(), semaphore = DispatchSemaphore(value: 0)
        private var heldPoint: Point?, entered = false, failLegacy = false
        private var values: [FavoritesNamespace: Data] = [:]
        private var reads = 0, deletes = 0
        var isHeld: Bool { lock.withLock { entered } }
        var readCount: Int { lock.withLock { reads } }
        var deleteCount: Int { lock.withLock { deletes } }
        func hold(_ point: Point) { lock.withLock { heldPoint = point; entered = false } }
        func release() { semaphore.signal() }
        func failLegacyOnce() { lock.withLock { failLegacy = true } }
        func set(_ bytes: Data?, _ namespace: FavoritesNamespace) { lock.withLock { values[namespace] = bytes } }
        func peek(_ namespace: FavoritesNamespace) -> Data? { lock.withLock { values[namespace] } }
        private func wait(_ point: Point) throws {
            let held = lock.withLock { () -> Bool in
                guard heldPoint == point else { return false }
                heldPoint = nil; entered = true; return true
            }
            if held {
                defer { lock.withLock { entered = false } }
                guard semaphore.wait(timeout: .now() + 8) == .success else { throw Failure.timeout }
            }
        }
        func read(_ namespace: FavoritesNamespace) throws -> Data? {
            lock.withLock { reads += 1 }; try wait(.read); return peek(namespace)
        }
        func replace(_ bytes: Data, _ url: URL) throws {
            if url.lastPathComponent.hasSuffix(".cleanup.json") { try wait(.pending) }
            try bytes.write(to: url, options: .atomic)
        }
        func remove(_ url: URL) throws { try wait(.remove); try FileManager.default.removeItem(at: url) }
        func delete(_ namespace: FavoritesNamespace, expected: Data) throws {
            try lock.withLock {
                if failLegacy { failLegacy = false; throw Failure.read }
                guard values[namespace] == expected else { throw FavoritesFileJournal.CleanupFailure.changedSource }
                values.removeValue(forKey: namespace); deletes += 1
            }
        }
    }
    private final class ResumeDisk: @unchecked Sendable {
        private let lock = NSLock(), semaphore = DispatchSemaphore(value: 0)
        private var bytes: Data?, reads = 0, writes = 0
        private var holdAt: Int?, failAt: Int?, failReadAt: Int?, held = false
        var readCount: Int { lock.withLock { reads } }
        var writeCount: Int { lock.withLock { writes } }
        var isHeld: Bool { lock.withLock { held } }
        func peek() -> Data? { lock.withLock { bytes } }
        func replace(_ data: Data?) { lock.withLock { bytes = data } }
        func holdWrite(after offset: Int = 1) { lock.withLock { holdAt = writes + offset } }
        func failWrite(after offset: Int = 1) { lock.withLock { failAt = writes + offset } }
        func failRead(after offset: Int = 1) { lock.withLock { failReadAt = reads + offset } }
        func release() { semaphore.signal() }
        func read() throws -> Data? {
            try lock.withLock {
                reads += 1
                if failReadAt == reads { failReadAt = nil; throw Failure.read }
                return bytes
            }
        }
        func write(_ data: Data) throws {
            let shouldHold = lock.withLock { () -> Bool in
                writes += 1
                if holdAt == writes { holdAt = nil; held = true; return true }
                return false
            }
            if shouldHold {
                defer { lock.withLock { held = false } }
                guard semaphore.wait(timeout: .now() + 8) == .success else { throw Failure.timeout }
            }
            try lock.withLock {
                if failAt == writes { failAt = nil; throw Failure.read }
                bytes = data
            }
        }
    }
    @MainActor private final class PodcastDisk {
        var records: [String: Data] = [:]
        var reads = 0, writes = 0, factories = 0
        var failWriteAt: Int?, failReadAt: Int?
        var onFactory: (() -> Void)?, onRead: (() -> Void)?, onWrite: (() -> Void)?
        func storage() -> PodcastPlaybackProgressStore.Storage {
            factories += 1; onFactory?()
            return .init(read: { [unowned self] namespace in
                reads += 1; onRead?()
                if reads == failReadAt { failReadAt = nil; throw Failure.read }
                return records[namespace.storageKey]
            }, write: { [unowned self] namespace, data in
                writes += 1
                if writes == failWriteAt { failWriteAt = nil; throw Failure.read }
                records[namespace.storageKey] = data; onWrite?()
            })
        }
    }
    @MainActor private final class IntroductionDisk {
        var source: Data?, metadata: Data?, guest: Data?
        var reads = 0, writes = 0, metadataReads = 0, metadataWrites = 0
        var failSourceWrite = false, failSourceRead = false
        var onRead: (() -> Void)?, onWrite: (() -> Void)?, onMetadataWrite: (() -> Void)?
        var storage: ReaderIntroductionStorage {
            .init(read: { [unowned self] in
                reads += 1; onRead?()
                if failSourceRead { failSourceRead = false; throw Failure.read }
                return source
            }, write: { [unowned self] data in
                writes += 1
                if failSourceWrite { failSourceWrite = false; throw Failure.read }
                source = data; onWrite?()
            }, cleanup: .init(read: { [unowned self] in metadataReads += 1; return metadata },
                write: { [unowned self] data in metadataWrites += 1; metadata = data; onMetadataWrite?() }))
        }
        func seed(_ uid: String? = "reader-A", completed: Bool = true) throws {
            let state = CanonicalSessionState()
            _ = state.adopt(uid.map { .init(uid: $0, email: "local@example.invalid", isEmailVerified: true) })
            let model = ReaderIntroductionModel(storage: storage)
            XCTAssertTrue(model.bindContext(state.contextTicket(), isCurrent: state.isCurrent)); XCTAssertTrue(model.start())
            if completed { XCTAssertTrue(model.complete()); XCTAssertTrue(model.replay()) }
            XCTAssertTrue(model.setSelectedTopicIDs(["film", "music"]))
            let guestModel = GuestReaderInterestsModel(storage: .init(read: { [unowned self] in guest }, write: { [unowned self] in guest = $0 }))
            let guestState = CanonicalSessionState(); _ = guestState.adopt(nil)
            XCTAssertTrue(guestModel.start())
            XCTAssertTrue(guestModel.save(["guest-topic"], context: guestState.contextTicket(), isCurrent: guestState.isCurrent))
        }
    }
    @MainActor private final class HistoryDisk {
        var records: [String: Data] = [:], metadata: Data?
        var reads = 0, writes = 0, metadataWrites = 0, normalEffects = 0
        var failWrite = false, failReadback = false, nextReadFails = false
        var onRead: (() -> Void)?, onWrite: (() -> Void)?, onMetadataWrite: (() -> Void)?
        var cleanup: ReadingHistoryModel.Storage.Cleanup {
            .init(readSource: { [unowned self] namespace in
                reads += 1; onRead?()
                if nextReadFails { nextReadFails = false; throw Failure.read }; return records[namespace.storageKey]
            }, writeSource: { [unowned self] namespace, data in
                writes += 1
                if failWrite { failWrite = false; throw Failure.read }
                records[namespace.storageKey] = data; onWrite?()
                if failReadback { failReadback = false; nextReadFails = true }
            }, readMetadata: { [unowned self] in metadata }, writeMetadata: { [unowned self] data in
                metadataWrites += 1; metadata = data; onMetadataWrite?()
            })
        }
        func seed() throws {
            for uid: String? in ["reader-A", "reader-B", nil] {
                let n = try XCTUnwrap(ReadingHistoryContext.confirmed(userID: uid).namespace)
                records[n.storageKey] = try ReadingHistoryRecordCodec.encode(.init(entries: [.init(articleID: "kept-history", read: true, progress: 0.42)]), namespace: n)
            }
            records["readArticleIds"] = Data("unowned legacy read IDs".utf8)
            records["readingProgress"] = Data("unowned legacy progress".utf8)
        }
    }
    private final class PushDisk: PushInstallationRecordStore, @unchecked Sendable {
        private let lock = NSLock()
        private var bytes: Data?
        private(set) var reads = 0, writes = 0
        var failRead = false
        func replace(_ value: Data?) { lock.withLock { bytes = value } }
        func peek() -> Data? { lock.withLock { bytes } }
        func readExistingData() throws -> Data? {
            try lock.withLock { reads += 1; if failRead { throw Failure.read }; return bytes }
        }
        func transaction(_ update: (Data?) throws -> Data) throws -> Data {
            try lock.withLock { let new = try update(bytes); writes += 1; bytes = new; return new }
        }
    }
    @MainActor private final class Fixture {
        let root: URL, configuration: ReaderDeletionHTTPTransport.Configuration
        let reads: ReadControl
        let recovery: ReaderTransitionRecovery, startup: ReaderSDKStartupState, auth: AuthService
        var user: User? = User("reader-A"), now: Int64 = 1_800_000_000_123
        let pushDisk = PushDisk()
        var includePushVault = false
        lazy var pushVault = PushInstallationVault(store: pushDisk, makeIdentity: { throw Failure.malformed })
        var httpGate: Gate?, httpFailure = false, httpHook: (() -> Void)?, credentialHook: (() -> Void)?
        var clockHook: (() -> Void)?, deadlineHook: (() -> Void)?, deadlineCancelHook: (() -> Void)?
        func seedPush(uid: String? = "reader-A", status: PushRegistrationReceipt.Status = .pending, ack: Bool = true) throws {
            let iid = "11111111-1111-4111-8111-111111111111"
            let binding = PushAcknowledgedInstallationBinding(schemaVersion: 1, installationId: iid,
                appId: configuration.appID, ownerUID: uid, ownerEpoch: 29, revision: 42, clientRevision: 3, status: status)
            let record = PushInstallationRecord(installationId: iid, key: String(repeating: "k", count: 48), revision: 3,
                intentHash: String(repeating: "a", count: 64), revisionStartedAt: Date(timeIntervalSince1970: 1_800_000_000),
                acknowledgedBinding: ack ? binding : nil)
            pushDisk.replace(try JSONEncoder().encode(record))
        }
        var readerSteps = 0, publications = 0, feedStarts = 0, factories = 0, sdkCalls = 0
        var requests: [URLRequest] = [], flows: [Flow] = [], tasks: [Task<Void, Never>] = []
        var gate: Gate?, allGates: [Gate] = []
        var factoryHook: (() -> Void)?
        var afterFactory: ((Model) -> Void)?
        let localDisk: LocalDisk
        let resumeDisk: ResumeDisk
        let resumeStore: ReaderResumeStore
        let podcastDisk: PodcastDisk
        lazy var podcastRuntime = PodcastProgressRuntime(disabled: false, storageFactory: { [unowned self] in podcastDisk.storage() }, recovery: recovery)
        let introductionDisk = IntroductionDisk()
        lazy var introductionModel = ReaderIntroductionModel(storage: introductionDisk.storage, recovery: recovery)
        let historyDisk = HistoryDisk()
        var includeHistoryModel = true, historyCapability = true
        lazy var historyRuntime = ReadingHistoryRuntime(disabled: false, transportFactory: { [unowned self] in
            historyDisk.normalEffects += 1
            return .init(storage: .init(read: { [unowned self] _ in historyDisk.normalEffects += 1; return nil },
                write: { [unowned self] _, _ in historyDisk.normalEffects += 1 }),
                observe: { [unowned self] _ in historyDisk.normalEffects += 1; return {} },
                synchronize: { [unowned self] in historyDisk.normalEffects += 1 })
        }, schedule: { [unowned self] _, _ in historyDisk.normalEffects += 1; return {} },
            markProfileRead: { [unowned self] _, _ in historyDisk.normalEffects += 1 }, recovery: recovery,
            cleanupStorage: historyCapability ? historyDisk.cleanup : nil)
        var includeIntroductionModel = true
        var includePodcastStore = true
        var includeResumeStore = true
        var localFactoryCalls = 0
        var localFactoryHook: (() -> Void)?
        var localJournal: FavoritesFileJournal?
        var timeouts: [@MainActor () -> Void] = []
        var localExpected: [FavoritesNamespace: (Data, Data)] = [:]
        var favoritesDirectory: URL { root.appendingPathComponent("favorites", isDirectory: true) }
        func favoritesFile(_ namespace: FavoritesNamespace) -> URL { favoritesDirectory.appendingPathComponent(namespace.recordBinding + ".json") }
        func localFactory() -> FavoritesFileJournal? {
            localFactoryCalls += 1; localFactoryHook?()
            if let localJournal { return localJournal }
            let disk = localDisk
            let journal = FavoritesFileJournal(rootDirectory: favoritesDirectory,
                legacyRead: { try disk.read($0) }, replace: { try disk.replace($0, $1) },
                legacyDelete: { try disk.delete($0, expected: $1) }, remove: { try disk.remove($0) })
            localJournal = journal; return journal
        }
        func seedFavorites() throws {
            try FileManager.default.createDirectory(at: favoritesDirectory, withIntermediateDirectories: true)
            for namespace in [try XCTUnwrap(FavoritesContext.confirmed(userID: "reader-A").namespace),
                              try XCTUnwrap(FavoritesContext.confirmed(userID: "reader-B").namespace), .guest] {
                let article = Article(id: namespace.recordBinding, name: "Original", slug: "original", content: "", intro: "", topicID: "topic", contentRevision: "r1")
                let entries = try JSONSerialization.jsonObject(with: JSONEncoder().encode([FavoritesRecord.Metadata(article)]))
                let v1 = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "namespace": namespace.recordBinding, "entries": entries], options: [.sortedKeys])
                let v2 = try FavoritesRecordCodec.encode(.init(articles: [article]), namespace: namespace)
                localDisk.set(v1, namespace); try v2.write(to: favoritesFile(namespace), options: .atomic)
                localExpected[namespace] = (v1, v2)
            }
        }
        lazy var operations = AuthOperationCoordinator(canonical: auth.state,
            actualUserID: { [unowned self] in user?.uid }, reauthenticationIdentity: auth.bootstrapIdentity)
        lazy var bridge = Bridge(canonical: auth.bootstrapIdentity, operations: operations, captureUser: { [unowned self] in
            guard let original = user else { return nil }
            return .init(uid: original.uid, isCurrent: { [unowned self] in user === original },
                reauthenticate: { [unowned self] _, permitted in
                    guard permitted() else { throw CancellationError() }
                    sdkCalls += 1
                    if let held = gate { gate = nil; await held.hold() }
                    guard permitted() else { throw CancellationError() }
                    return .init(uid: original.uid, authTimeMs: (now / 1_000) * 1_000)
                }, deletionCredentials: { [unowned self] proof, _ in
                    credentialHook?()
                    return .init(ownerUID: original.uid, projectID: configuration.projectID, appID: configuration.appID,
                        idToken: "local.id." + proof.action.actionID.uuidString,
                        appCheckToken: "local.app." + proof.action.actionID.uuidString, authTimeMs: proof.authTimeMs,
                        authValidUntilMs: now + 60_000, appCheckValidUntilMs: now + 60_000)
                }, email: "original@example.invalid", supportsPassword: original.supportsPassword,
                appleSubject: "original-apple-subject", googleSubject: "original-google-subject")
        }, nowMilliseconds: { [unowned self] in now })
        lazy var googleService = GoogleSignInService(reauthenticationProvider: { _, _ in throw CancellationError() })
        lazy var delegate = AppDelegate(startup: startup, identity: auth.bootstrapIdentity,
            actualUserID: { [unowned self] in user?.uid })
        lazy var vm = ArticleViewModel(startup: startup, identity: auth.bootstrapIdentity,
            actualUserID: { [unowned self] in user?.uid }, readEffects: .init())
        init(restoring originalRoot: URL? = nil, localDisk: LocalDisk? = nil,
             resumeDisk: ResumeDisk? = nil, podcastDisk: PodcastDisk? = nil) throws {
            self.podcastDisk = podcastDisk ?? PodcastDisk()
            self.localDisk = localDisk ?? LocalDisk()
            let positions = resumeDisk ?? ResumeDisk(); self.resumeDisk = positions
            resumeStore = ReaderResumeStore(storage: .init(read: { try positions.read() }, write: { try positions.write($0) }))
            let control = ReadControl(); reads = control
            root = originalRoot ?? FileManager.default.temporaryDirectory.appendingPathComponent("recovery-presentation-" + UUID().uuidString)
            configuration = try .init(projectID: "local-deletion", appID: "1:123456789:ios:abcdef123456",
                endpointURL: try XCTUnwrap(URL(string: "https://deletion.example.invalid/reader")))
            recovery = ReaderTransitionRecovery(store: .init(rootDirectory: root, beforeRead: { try control.read() }))
            startup = ReaderSDKStartupState(legacyRecovery: recovery); auth = AuthService(startup: startup)
        }
        var checkpointURL: URL { root.appendingPathComponent("reader-deletion-v1.json") }
        func seed(_ records: Records = .checkpoint) async throws {
            let previous = ReaderTransitionRecovery(store: .init(rootDirectory: root))
            try await previous.bootstrap()
            _ = try await previous.seal(binding: .init(ownerUID: "reader-A", epoch: 7))
            if records != .marker {
                _ = try await previous.recordDeletion(request: .init(expectedUID: "reader-A", membershipEpoch: 7), phase: .parent,
                    configurationDigest: ReaderTransitionRecoveryStore.deletionConfigurationDigest(
                        projectID: configuration.projectID, appID: configuration.appID, endpoint: configuration.endpointURL))
            }
            if records == .corrupt { try Data("{invalid".utf8).write(to: checkpointURL, options: .atomic) }
        }
        @discardableResult func launch(_ uid: String? = "reader-A") -> Task<Void, Never>? {
            vm.start(readerSteps: [{ [unowned self] _ in feedStarts += 1 }])
            let task = delegate.runAccountStartup(authOnly: {}, readerSteps: [{ [unowned self] in readerSteps += 1 }],
                observeAuth: { [unowned self] in observe(uid) },
                releaseReader: { [unowned self] in _ = auth.resumeReaderAfterLocalRecovery() })
            if let task { tasks.append(task) }; return task
        }
        func observe(_ uid: String?) {
            if user?.uid != uid { user = uid.map { User($0) } }
            let session = uid.map { ReaderAccountSession(uid: $0, email: "canonical@example.invalid", isEmailVerified: true) }
            _ = auth.observeIdentity(session, currentUserID: { [unowned self] in user?.uid },
                revokeReader: { [unowned self] permitted in auth.state.suspend(stillPermitted: permitted) != nil },
                publishReader: { [unowned self] permitted in
                    guard let context = auth.state.adopt(session, stillPermitted: permitted) else { return nil }
                    publications += 1; return context
                })
        }
        func factory(_ provider: AuthService.RecoveryProvider, _ prompts: AuthService.RecoveryPrompts) -> Model? {
            factories += 1; factoryHook?()
            let execute: @MainActor (URLRequest) async throws -> (Data, HTTPURLResponse) = { [unowned self] request in
                requests.append(request)
                if let held = httpGate { httpGate = nil; await held.hold() }
                httpHook?()
                if httpFailure { httpFailure = false; throw Failure.timeout }
                return try response(request)
            }
            let clock: @MainActor () -> Int64 = { [unowned self] in clockHook?(); return now }
            let model: Model?
            switch provider {
            case .email:
                model = auth.makeEmailReaderAccountDeletion(configuration: configuration, reauthentication: bridge,
                    prompt: prompts.email, makeCredential: { _, _ in "local-credential" }, execute: execute, now: clock,
                    scheduleTimeout: { [unowned self] _, action in timeouts.append(action); deadlineHook?(); return { [weak self] in self?.deadlineCancelHook?() } },
                    resumingAfterRestart: true, localJournalFactory: { [unowned self] in localFactory() },
                    localResumeStore: includeResumeStore ? resumeStore : nil,
                    localPodcastStore: includePodcastStore ? podcastRuntime.localCleanupStore() : nil,
                    localIntroductionModel: includeIntroductionModel ? introductionModel : nil,
                    localHistoryModel: includeHistoryModel ? historyRuntime.localCleanupModel() : nil,
                    pushInstallationVault: includePushVault ? pushVault : nil)
            case .apple:
                model = auth.makeAppleReaderAccountDeletion(configuration: configuration, reauthentication: bridge,
                    prompt: prompts.apple, makeCredential: { _, _ in "local-credential" }, execute: execute, now: clock,
                    scheduleTimeout: { [unowned self] _, action in timeouts.append(action); deadlineHook?(); return { [weak self] in self?.deadlineCancelHook?() } },
                    resumingAfterRestart: true, localJournalFactory: { [unowned self] in localFactory() },
                    localResumeStore: includeResumeStore ? resumeStore : nil,
                    localPodcastStore: includePodcastStore ? podcastRuntime.localCleanupStore() : nil,
                    localIntroductionModel: includeIntroductionModel ? introductionModel : nil,
                    localHistoryModel: includeHistoryModel ? historyRuntime.localCleanupModel() : nil,
                    pushInstallationVault: includePushVault ? pushVault : nil)
            case .google:
                model = auth.makeGoogleReaderAccountDeletion(configuration: configuration, reauthentication: bridge,
                    prompt: prompts.google, makeCredential: { _, _ in "local-credential" }, execute: execute, now: clock,
                    scheduleTimeout: { [unowned self] _, action in timeouts.append(action); deadlineHook?(); return { [weak self] in self?.deadlineCancelHook?() } },
                    resumingAfterRestart: true, localJournalFactory: { [unowned self] in localFactory() },
                    localResumeStore: includeResumeStore ? resumeStore : nil,
                    localPodcastStore: includePodcastStore ? podcastRuntime.localCleanupStore() : nil,
                    localIntroductionModel: includeIntroductionModel ? introductionModel : nil,
                    localHistoryModel: includeHistoryModel ? historyRuntime.localCleanupModel() : nil,
                    pushInstallationVault: includePushVault ? pushVault : nil)
            }
            if let model { afterFactory?(model) }
            return model
        }
        func prepare(_ ticket: Ticket, provider: AuthService.RecoveryProvider = .email) -> Flow? {
            let flow = auth.prepareAccountRecovery(ticket: ticket, provider: provider, configuration: configuration,
                googleService: googleService,
                supportedProviders: { [unowned self] in bridge.supportedMethods(context: $0.context) },
                factory: { [unowned self] in factory($0, $1) })
            if let flow { flows.append(flow) }; return flow
        }
        func confirm(_ flow: Flow, userConfirmed: Bool = true) -> Bool {
            auth.confirmAccountRecovery(flow, configuration: configuration, userConfirmed: userConfirmed)
        }
        func holdSDK() -> Gate { let value = Gate(); gate = value; allGates.append(value); return value }
        func response(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
            guard let bytes = request.httpBody, let body = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  let uid = body["expectedUID"] as? String, let epoch = body["membershipEpoch"] as? Int64,
                  let url = request.url else { throw Failure.malformed }
            if body["scope"] as? String == Contract.pushPreparationScope || body["scope"] as? String == Contract.pushScope {
                let original = try JSONDecoder().decode(Contract.PushRequest.self, from: bytes)
                return (try pushResponse(original), try XCTUnwrap(HTTPURLResponse(url: url,
                    statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])))
            }
            let parent = try Contract.Request(expectedUID: uid, membershipEpoch: epoch)
            let ledger = body["scope"] as? String == Contract.ledgerScope
            let requestID: String
            if ledger {
                requestID = try Contract.LedgerRequest(expectedUID: uid, membershipEpoch: epoch,
                    parentRequestID: try XCTUnwrap(body["parentRequestID"] as? String)).requestID
            } else { requestID = parent.requestID }
            var reply: [String: Any] = ["requestID": requestID, "scope": ledger ? Contract.ledgerScope : Contract.scope,
                "status": ledger ? "ledgerDataRemoved" : "scopedCloudDataRemoved", "accountDeletionComplete": false,
                "unresolved": ledger ? Contract.ledgerUnresolved : Contract.unresolved]
            if ledger { reply["parentRequestID"] = parent.requestID; reply["removedReceiptDocuments"] = 1; reply["removedRevisionDocuments"] = 1 }
            else { reply["removedFavoriteDocuments"] = 2 }
            return (try JSONSerialization.data(withJSONObject: reply), try XCTUnwrap(HTTPURLResponse(url: url,
                statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])))
        }
        func pushResponse(_ r: Contract.PushRequest) throws -> Data {
            let i = r.installation, c = i.expected
            var reply: [String: Any]
            if r.scope == Contract.pushPreparationScope {
                reply = ["schemaVersion": 1, "scope": r.scope, "expectedUID": r.expectedUID,
                    "membershipEpoch": r.membershipEpoch, "parentRequestID": r.parentRequestID, "ledgerRequestID": r.ledgerRequestID,
                    "installationId": i.installationId, "status": "prepared", "preparedOnly": true, "retirementComplete": false,
                    "snapshot": ["schemaVersion": 1, "requestId": i.requestId, "installationId": i.installationId,
                        "ownerUID": r.expectedUID, "appId": configuration.appID, "ownerEpoch": c.ownerEpoch,
                        "revision": c.revision, "clientRevision": c.clientRevision, "stateDigest": String(repeating: "d", count: 64)]]
            } else {
                reply = ["requestID": r.requestID, "scope": r.scope, "parentRequestID": r.parentRequestID,
                    "ledgerRequestID": r.ledgerRequestID, "installationId": i.installationId, "status": "installationRetired",
                    "retirementReceipt": ["schemaVersion": 1, "status": "retired", "requestId": i.requestId,
                        "installationId": i.installationId, "ownerUID": r.expectedUID, "appId": configuration.appID,
                        "ownerEpoch": c.ownerEpoch, "revision": c.revision + 1, "clientRevision": c.clientRevision,
                        "retiredAtMs": now, "retiredChallenges": 1, "removedTokenOwners": 1,
                        "preservedForeignChallenges": 0, "preservedForeignTokenOwners": 0, "preservedUnprovenTokenOwners": 0,
                        "accountDeletionComplete": false, "historicalMaterialComplete": false, "deliveriesRecalled": false]]
            }
            reply["accountDeletionComplete"] = false; reply["historicalMaterialComplete"] = false
            reply["deliveriesRecalled"] = false; reply["unresolved"] = Contract.pushUnresolved
            return try JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys])
        }
        func close() async {
            httpHook = nil; credentialHook = nil; clockHook = nil; deadlineHook = nil; deadlineCancelHook = nil
            factoryHook = nil; afterFactory = nil; localFactoryHook = nil; localDisk.release(); resumeDisk.release(); reads.release(); allGates.forEach { $0.release() }
            flows.forEach { auth.cancelAccountRecovery($0) }
            for task in tasks { task.cancel(); await task.value }
            for _ in 0..<2_000 {
                if flows.allSatisfy({ !$0.coordinator.hasPhysicalFlight }) && !recovery.isBusy && localJournal?.isPhysicallyIdle != false { break }
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            try? FileManager.default.removeItem(at: root)
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }
    private func fixture(_ records: Records = .checkpoint, launch: Bool = true) async throws -> Fixture {
        let value = try Fixture(); addTeardownBlock { @MainActor in await value.close() }
        try await value.seed(records)
        if launch, let task = value.launch() { await task.value }
        return value
    }
    private func eventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<2_000 { if predicate() { return }; try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTFail("Expected actual recovery stage was not reached", file: file, line: line)
    }
    private func ticket(_ f: Fixture) throws -> Ticket {
        guard case .deletion(let ticket) = f.auth.accountRecoveryPresentation else { throw Failure.malformed }
        return ticket
    }
    private func assertClosed(_ f: Fixture, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(f.auth.state.snapshot.context, .unresolved, file: file, line: line)
        XCTAssertEqual(f.readerSteps, 0, file: file, line: line); XCTAssertEqual(f.publications, 0, file: file, line: line)
        XCTAssertEqual(f.feedStarts, 0, file: file, line: line); XCTAssertFalse(f.recovery.admission.isAllowed, file: file, line: line)
        XCTAssertFalse(f.startup.permitsReaderServices(identity: f.auth.bootstrapIdentity), file: file, line: line)
    }
    private func password(_ f: Fixture, _ flow: Flow) async throws -> (action: Model.ActionTicket, task: Task<Void, Never>) {
        await eventually { flow.prompts.email.presentation != nil }
        let presentation = try XCTUnwrap(flow.prompts.email.presentation), form = presentation.form
        form.form.password = "LocalFresh!"
        let request = try XCTUnwrap(form.captureSubmission())
        let task = Task { await form.submit(request) }; f.tasks.append(task); return (presentation.action, task)
    }

    func testProjectionWaitsForPhysicalReadAndRepeatedDisplayDoesNotReadAgain() async throws {
        let f = try await fixture(launch: false)
        guard case .checking = f.auth.accountRecoveryPresentation else { return XCTFail("Unopened disk must not supply a request") }
        f.reads.holdNext(); let launch = try XCTUnwrap(f.launch())
        await eventually { f.reads.count == 1 }
        for _ in 0..<100 {
            guard case .checking = f.auth.accountRecoveryPresentation else { return XCTFail("Held read must remain checking") }
        }
        XCTAssertEqual(f.reads.count, 1); XCTAssertEqual(f.factories, 0); XCTAssertTrue(f.requests.isEmpty)
        f.reads.release(); await launch.value
        let original = try ticket(f), count = f.reads.count
        for _ in 0..<100 { XCTAssertEqual(try ticket(f), original) }
        XCTAssertEqual(f.reads.count, count); XCTAssertEqual(original.context, f.auth.bootstrapIdentity.contextTicket())
        XCTAssertEqual(original.checkpoint.request.expectedUID, "reader-A"); assertClosed(f)
    }

    func testGenericMarkerStaysProtectedWithoutInventedDeletionTicket() async throws {
        let f = try await fixture(.marker)
        guard case .protected = f.auth.accountRecoveryPresentation else { return XCTFail("Generic seal has no deletion intent") }
        XCTAssertNil(f.auth.accountRecoveryFlow); XCTAssertEqual(f.factories, 0); XCTAssertTrue(f.requests.isEmpty); assertClosed(f)
    }

    func testCorruptCheckpointAndReadFailureStayUnavailableWithoutRepairOrFactory() async throws {
        let corrupt = try await fixture(.corrupt), before = try Data(contentsOf: corrupt.checkpointURL)
        guard case .unavailable = corrupt.auth.accountRecoveryPresentation else { return XCTFail("Malformed checkpoint must fail closed") }
        XCTAssertEqual(try Data(contentsOf: corrupt.checkpointURL), before); assertClosed(corrupt)
        let failed = try await fixture(launch: false); failed.reads.failNext()
        if let task = failed.launch() { await task.value }
        guard case .unavailable = failed.auth.accountRecoveryPresentation else { return XCTFail("Read failure must stay unavailable") }
        XCTAssertNil(failed.auth.accountRecoveryFlow); XCTAssertEqual(failed.factories, 0); assertClosed(failed)
    }

    func testOtherAccountAndGuestProjectionDoNotExposeOriginalRequest() async throws {
        for uid in ["reader-B", nil] as [String?] {
            let f = try await fixture(launch: false)
            if let task = f.launch(uid) { await task.value }
            if case .deletion = f.auth.accountRecoveryPresentation { XCTFail("Different owner must not see original deletion request") }
            XCTAssertNil(f.auth.accountRecoveryFlow); XCTAssertTrue(f.requests.isEmpty); assertClosed(f)
        }
    }

    func testMissingConfigurationAndWrongDigestRejectBeforeInjectedFactory() async throws {
        let f = try await fixture(), original = try ticket(f)
        var invoked = 0, capabilityReads = 0
        XCTAssertFalse(f.auth.canPrepareAccountRecovery(ticket: original, configuration: nil))
        XCTAssertNil(f.auth.prepareAccountRecovery(ticket: original, provider: .email, configuration: nil,
            supportedProviders: { ticket in capabilityReads += 1; return f.bridge.supportedMethods(context: ticket.context) },
            factory: { _, _ in invoked += 1; return nil }))
        let other = try ReaderDeletionHTTPTransport.Configuration(projectID: f.configuration.projectID, appID: f.configuration.appID,
            endpointURL: try XCTUnwrap(URL(string: "https://other.example.invalid/reader")))
        XCTAssertFalse(f.auth.canPrepareAccountRecovery(ticket: original, configuration: other))
        XCTAssertNil(f.auth.prepareAccountRecovery(ticket: original, provider: .email, configuration: other,
            supportedProviders: { ticket in capabilityReads += 1; return f.bridge.supportedMethods(context: ticket.context) },
            factory: { _, _ in invoked += 1; return nil }))
        XCTAssertEqual(invoked, 0); XCTAssertEqual(capabilityReads, 0); XCTAssertNil(f.auth.accountRecoveryFlow); assertClosed(f)
    }

    func testPreparingAndReopeningPreserveOneAuthOwnedFlowWithoutAutomaticSend() async throws {
        let f = try await fixture(), original = try ticket(f), flow = try XCTUnwrap(f.prepare(original))
        let reopened = try XCTUnwrap(f.prepare(original))
        XCTAssertEqual(flow.id, reopened.id); XCTAssertTrue(flow.coordinator === reopened.coordinator)
        XCTAssertTrue(flow.prompts.email === reopened.prompts.email); XCTAssertEqual(f.factories, 1)
        XCTAssertEqual(f.auth.accountRecoveryFlow?.id, flow.id); XCTAssertFalse(f.confirm(flow, userConfirmed: false))
        XCTAssertFalse(f.auth.confirmAccountRecoveryLedger(flow, configuration: f.configuration, userConfirmed: true))
        XCTAssertTrue(f.requests.isEmpty); XCTAssertEqual(f.sdkCalls, 0); XCTAssertNil(flow.prompts.email.presentation)
        XCTAssertNil(f.prepare(original, provider: .apple)); XCTAssertEqual(f.factories, 1); assertClosed(f)
    }

    func testExplicitParentAndLedgerConfirmationsUseSameFlowAndFreshProviderActions() async throws {
        let f = try await fixture(), flow = try XCTUnwrap(f.prepare(try ticket(f)))
        XCTAssertTrue(f.confirm(flow)); let first = try await password(f, flow)
        let action = first.action
        await first.task.value; await eventually { flow.coordinator.canBeginLedgerCleanup }
        XCTAssertEqual(f.requests.count, 1)
        let reopened = try XCTUnwrap(f.prepare(try ticket(f))); XCTAssertEqual(reopened.id, flow.id)
        XCTAssertFalse(f.auth.confirmAccountRecoveryLedger(flow, configuration: f.configuration, userConfirmed: false))
        f.now += 5_000
        XCTAssertTrue(f.auth.confirmAccountRecoveryLedger(flow, configuration: f.configuration, userConfirmed: true))
        let second = try await password(f, flow)
        let ledgerAction = second.action
        XCTAssertNotEqual(action.actionID, ledgerAction.actionID); XCTAssertEqual(ledgerAction.phase, .mutationLedger)
        await second.task.value; await eventually { flow.coordinator.status == .ledgerDataRemoved && !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(f.factories, 1); XCTAssertEqual(f.sdkCalls, 2); XCTAssertEqual(f.requests.count, 2)
        XCTAssertFalse(flow.coordinator.accountDeletionComplete); assertClosed(f)
    }

    func testCancellationWhileSDKHeldKeepsOwnedFlowAndCannotCreateReplacement() async throws {
        let f = try await fixture(), original = try ticket(f), flow = try XCTUnwrap(f.prepare(original)), held = f.holdSDK()
        XCTAssertTrue(f.confirm(flow)); let submitted = try await password(f, flow)
        await eventually { held.entered }; f.auth.cancelAccountRecovery(flow)
        XCTAssertTrue(flow.coordinator.hasPhysicalFlight); XCTAssertTrue(f.operations.isBusy)
        XCTAssertEqual(f.auth.accountRecoveryFlow?.id, flow.id)
        let same = try XCTUnwrap(f.prepare(original)); XCTAssertEqual(same.id, flow.id)
        XCTAssertNil(f.prepare(original, provider: .google)); XCTAssertEqual(f.factories, 1)
        XCTAssertFalse(f.confirm(flow)); XCTAssertTrue(f.requests.isEmpty)
        held.release(); await submitted.task.value; await eventually { !flow.coordinator.hasPhysicalFlight && !f.operations.isBusy }
        XCTAssertTrue(f.requests.isEmpty); XCTAssertFalse(flow.coordinator.abortBeforeSubmission()); assertClosed(f)
    }

    func testOldTicketAndFlowCannotBorrowReturnedAccountGeneration() async throws {
        let f = try await fixture(), original = try ticket(f), flow = try XCTUnwrap(f.prepare(original))
        f.observe("reader-B"); f.observe("reader-A")
        XCTAssertNotEqual(try ticket(f).context, original.context)
        XCTAssertFalse(f.auth.canUseAccountRecoveryFlow(flow, configuration: f.configuration))
        XCTAssertFalse(f.confirm(flow)); XCTAssertNil(f.prepare(original)); XCTAssertEqual(f.factories, 1)
        XCTAssertTrue(f.requests.isEmpty); XCTAssertEqual(f.sdkCalls, 0); assertClosed(f)
    }

    func testFactoryAccountReentryRejectsOriginalTicketBeforePresentationCommit() async throws {
        let f = try await fixture(), original = try ticket(f)
        f.factoryHook = { f.factoryHook = nil; f.observe("reader-B"); f.observe("reader-A") }
        XCTAssertNil(f.prepare(original)); XCTAssertEqual(f.factories, 1)
        XCTAssertNil(f.auth.accountRecoveryFlow); XCTAssertTrue(f.requests.isEmpty); XCTAssertEqual(f.sdkCalls, 0)
        XCTAssertFalse(f.auth.canPrepareAccountRecovery(ticket: original, configuration: f.configuration))
        let current = try ticket(f)
        XCTAssertTrue(f.auth.canPrepareAccountRecovery(ticket: current, configuration: f.configuration))
        let fresh = try XCTUnwrap(f.prepare(current))
        XCTAssertEqual(fresh.ticket.context, current.context); XCTAssertEqual(f.factories, 2)
        XCTAssertTrue(f.requests.isEmpty); assertClosed(f)
    }

    func testRejectedFactoryCannotDiscardAnAlreadyStartedCoordinatorReservation() async throws {
        let f = try await fixture(), original = try ticket(f)
        var orphan: Model?
        f.afterFactory = { model in
            f.afterFactory = nil; orphan = model
            XCTAssertTrue(model.beginResumption(context: f.auth.bootstrapIdentity.contextTicket(), userConfirmed: true))
            XCTAssertTrue(model.hasPhysicalFlight)
            f.observe("reader-B"); f.observe("reader-A")
        }
        XCTAssertNil(f.prepare(original)); XCTAssertEqual(f.factories, 1)
        let held = try XCTUnwrap(orphan)
        XCTAssertTrue(held.hasWriteBarrier)
        XCTAssertFalse(f.auth.canPrepareAccountRecovery(ticket: try ticket(f), configuration: f.configuration))
        XCTAssertNil(f.prepare(try ticket(f))); XCTAssertEqual(f.factories, 1)
        await eventually { !held.hasPhysicalFlight }
        XCTAssertTrue(held.hasWriteBarrier)
        XCTAssertTrue(f.requests.isEmpty); XCTAssertEqual(f.sdkCalls, 0); assertClosed(f)
    }

    func testFinalPublicationAccountReentryRetiresOnlyIdleFlowAndAllowsFreshPreparation() async throws {
        let f = try await fixture(), original = try ticket(f)
        var reentered = false
        var rejected: Flow?
        let observation = f.auth.objectWillChange.sink {
            guard !reentered, let visible = f.auth.accountRecoveryFlow else { return }
            reentered = true; rejected = visible
            XCTAssertFalse(visible.coordinator.hasPhysicalFlight)
            XCTAssertNil(visible.coordinator.requestID)
            f.observe("reader-B"); f.observe("reader-A")
        }
        defer { observation.cancel() }
        XCTAssertNil(f.prepare(original)); XCTAssertTrue(reentered); XCTAssertEqual(f.factories, 1)
        let old = try XCTUnwrap(rejected)
        XCTAssertNil(f.auth.accountRecoveryFlow); XCTAssertFalse(f.confirm(old))
        XCTAssertTrue(f.requests.isEmpty); XCTAssertEqual(f.sdkCalls, 0)
        let current = try ticket(f)
        XCTAssertNotEqual(current.context, original.context)
        XCTAssertTrue(f.auth.canPrepareAccountRecovery(ticket: current, configuration: f.configuration))
        let fresh = try XCTUnwrap(f.prepare(current))
        XCTAssertNotEqual(fresh.id, old.id); XCTAssertFalse(fresh.coordinator === old.coordinator)
        XCTAssertEqual(f.auth.accountRecoveryFlow?.id, fresh.id); XCTAssertEqual(f.factories, 2)
        XCTAssertTrue(f.requests.isEmpty); assertClosed(f)
    }

    func testChangedConfigurationCannotConfirmPreviouslyPreparedFlow() async throws {
        let f = try await fixture(), flow = try XCTUnwrap(f.prepare(try ticket(f)))
        let other = try ReaderDeletionHTTPTransport.Configuration(projectID: "other-project", appID: f.configuration.appID,
            endpointURL: f.configuration.endpointURL)
        XCTAssertFalse(f.auth.canUseAccountRecoveryFlow(flow, configuration: other))
        XCTAssertFalse(f.auth.confirmAccountRecovery(flow, configuration: other, userConfirmed: true))
        XCTAssertFalse(f.auth.confirmAccountRecoveryLedger(flow, configuration: other, userConfirmed: true))
        XCTAssertFalse(f.auth.confirmAccountRecovery(flow, configuration: nil, userConfirmed: true))
        XCTAssertTrue(f.requests.isEmpty); XCTAssertNil(flow.prompts.email.presentation); assertClosed(f)
    }

    func testNilFactoryResultDoesNotPublishFlowOrBeginProvider() async throws {
        let f = try await fixture(), original = try ticket(f)
        var count = 0
        XCTAssertNil(f.auth.prepareAccountRecovery(ticket: original, provider: .email, configuration: f.configuration, googleService: f.googleService,
            supportedProviders: { f.bridge.supportedMethods(context: $0.context) },
            factory: { _, _ in count += 1; return nil }))
        XCTAssertEqual(count, 1); XCTAssertNil(f.auth.accountRecoveryFlow)
        XCTAssertTrue(f.requests.isEmpty); XCTAssertEqual(f.sdkCalls, 0); assertClosed(f)
    }

    func testUnsupportedEmailDoesNotReserveFlowOrBlockSubsequentSupportedGoogleChoice() async throws {
        let f = try await fixture(), original = try ticket(f)
        f.user?.supportsPassword = false
        XCTAssertNil(f.prepare(original, provider: .email))
        XCTAssertEqual(f.factories, 0); XCTAssertNil(f.auth.accountRecoveryFlow)
        XCTAssertFalse(f.operations.isBusy); XCTAssertTrue(f.requests.isEmpty); XCTAssertEqual(f.sdkCalls, 0)
        let google = try XCTUnwrap(f.prepare(original, provider: .google))
        XCTAssertEqual(google.provider, .google); XCTAssertEqual(f.factories, 1)
        XCTAssertEqual(f.auth.accountRecoveryFlow?.id, google.id)
        XCTAssertNil(google.prompts.google.presentation); XCTAssertTrue(f.requests.isEmpty)
        XCTAssertEqual(f.sdkCalls, 0); assertClosed(f)
    }

    func testCapabilityHookAccountReentryCannotPrepareOldTicketEvenWhenReturningSupport() async throws {
        let f = try await fixture(), original = try ticket(f)
        var factories = 0
        XCTAssertNil(f.auth.prepareAccountRecovery(ticket: original, provider: .email, configuration: f.configuration,
            googleService: f.googleService, supportedProviders: { _ in
                f.observe("reader-B"); f.observe("reader-A"); return [.email]
            }, factory: { provider, prompts in factories += 1; return f.factory(provider, prompts) }))
        XCTAssertEqual(factories, 0); XCTAssertEqual(f.factories, 0); XCTAssertNil(f.auth.accountRecoveryFlow)
        let current = try ticket(f)
        XCTAssertNotEqual(current.context, original.context)
        XCTAssertNotNil(f.prepare(current)); XCTAssertEqual(f.factories, 1)
        XCTAssertTrue(f.requests.isEmpty); XCTAssertEqual(f.sdkCalls, 0); assertClosed(f)
    }

    private func ledgerReady(_ f: Fixture) async throws -> Flow {
        let flow = try XCTUnwrap(f.prepare(try ticket(f)))
        XCTAssertTrue(f.confirm(flow))
        let first = try await password(f, flow); await first.task.value
        await eventually { flow.coordinator.canBeginLedgerCleanup }
        f.now += 5_000
        XCTAssertTrue(f.auth.confirmAccountRecoveryLedger(flow, configuration: f.configuration, userConfirmed: true))
        let second = try await password(f, flow); await second.task.value
        await eventually { flow.coordinator.status == .ledgerDataRemoved && !flow.coordinator.hasPhysicalFlight }
        return flow
    }
    private func localReady(_ f: Fixture, _ flow: Flow) async throws -> Model.LocalFavoritesConfirmation {
        XCTAssertTrue(f.auth.prepareAccountRecoveryLocalFavorites(flow, configuration: f.configuration))
        await eventually { flow.coordinator.localFavoritesStatus == .ready && !flow.coordinator.hasPhysicalFlight }
        return try XCTUnwrap(flow.coordinator.localFavoritesConfirmation)
    }
    private func localConfirm(_ f: Fixture, _ flow: Flow, _ confirmation: Model.LocalFavoritesConfirmation) -> Bool {
        f.auth.confirmAccountRecoveryLocalFavorites(flow, confirmation: confirmation,
            configuration: f.configuration, userConfirmed: true)
    }
    private func assertFavorites(_ f: Fixture, removed: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        let owner = try XCTUnwrap(FavoritesContext.confirmed(userID: "reader-A").namespace)
        for (namespace, bytes) in f.localExpected {
            if removed && namespace == owner {
                XCTAssertNil(f.localDisk.peek(namespace), file: file, line: line)
                XCTAssertFalse(FileManager.default.fileExists(atPath: f.favoritesFile(namespace).path), file: file, line: line)
            } else {
                XCTAssertEqual(f.localDisk.peek(namespace), bytes.0, file: file, line: line)
                XCTAssertEqual(try Data(contentsOf: f.favoritesFile(namespace)), bytes.1, file: file, line: line)
            }
        }
        assertClosed(f, file: file, line: line)
    }

    func testLedgerReceiptAndRepeatedDisplayNeverConstructOrPurgeLocalJournal() async throws {
        let f = try await fixture(); try f.seedFavorites()
        let flow = try await ledgerReady(f)
        for _ in 0..<100 {
            XCTAssertTrue(flow.coordinator.canPrepareLocalFavoritesCleanup)
            XCTAssertNil(flow.coordinator.localFavoritesMessage)
            XCTAssertNil(flow.coordinator.localFavoritesConfirmation)
        }
        XCTAssertEqual(f.localFactoryCalls, 0); XCTAssertEqual(f.localDisk.readCount, 0)
        XCTAssertEqual(f.localDisk.deleteCount, 0); try assertFavorites(f, removed: false)
        let confirmation = try await localReady(f, flow)
        XCTAssertEqual(f.localFactoryCalls, 1); XCTAssertEqual(f.requests.count, 2)
        try assertFavorites(f, removed: false)
        XCTAssertFalse(f.auth.confirmAccountRecoveryLocalFavorites(flow, confirmation: confirmation,
            configuration: f.configuration, userConfirmed: false))
        try assertFavorites(f, removed: false)
        XCTAssertTrue(localConfirm(f, flow, confirmation))
        XCTAssertFalse(localConfirm(f, flow, confirmation))
        await eventually { flow.coordinator.localFavoritesStatus == .removed && !flow.coordinator.hasPhysicalFlight }
        try assertFavorites(f, removed: true)
        XCTAssertEqual(f.localDisk.deleteCount, 1); XCTAssertEqual(f.requests.count, 2)
        XCTAssertEqual(flow.coordinator.localFavoritesReceipt?.namespace, FavoritesContext.confirmed(userID: "reader-A").namespace)
        XCTAssertEqual(flow.coordinator.localFavoritesReceipt?.requestID, flow.ticket.checkpoint.request.requestID)
        XCTAssertEqual(flow.coordinator.localFavoritesReceipt?.transitionID, flow.ticket.checkpoint.marker.transitionID)
        XCTAssertEqual(flow.coordinator.localFavoritesReceipt?.configurationDigest, flow.ticket.checkpoint.configurationDigest)
        XCTAssertFalse(flow.coordinator.accountDeletionComplete)
        XCTAssertFalse(f.auth.prepareAccountRecoveryLocalFavorites(flow, configuration: f.configuration))
    }

    func testLocalCancelConsumesConfirmationAndNewReadRequiresFreshConfirmation() async throws {
        let f = try await fixture(); try f.seedFavorites(); let flow = try await ledgerReady(f)
        let old = try await localReady(f, flow)
        f.auth.cancelAccountRecoveryLocalFavorites(flow)
        XCTAssertEqual(flow.coordinator.localFavoritesStatus, .cancelled)
        XCTAssertNil(flow.coordinator.localFavoritesConfirmation); XCTAssertFalse(localConfirm(f, flow, old))
        try assertFavorites(f, removed: false)
        let fresh = try await localReady(f, flow)
        XCTAssertNotEqual(fresh, old); XCTAssertEqual(f.localFactoryCalls, 1)
        XCTAssertFalse(localConfirm(f, flow, old)); XCTAssertTrue(localConfirm(f, flow, fresh))
        await eventually { flow.coordinator.localFavoritesStatus == .removed }
        try assertFavorites(f, removed: true)
    }

    func testLocalJournalFactoryAccountRoundTripRejectsOriginalBeforeDisk() async throws {
        let f = try await fixture(); try f.seedFavorites(); let flow = try await ledgerReady(f)
        f.localFactoryHook = { f.localFactoryHook = nil; f.observe("reader-B"); f.observe("reader-A") }
        XCTAssertFalse(f.auth.prepareAccountRecoveryLocalFavorites(flow, configuration: f.configuration))
        XCTAssertEqual(f.localFactoryCalls, 1); XCTAssertEqual(f.localDisk.readCount, 0)
        XCTAssertNil(flow.coordinator.localFavoritesConfirmation); XCTAssertNil(flow.coordinator.localFavoritesReceipt)
        XCTAssertFalse(flow.coordinator.hasPhysicalFlight); try assertFavorites(f, removed: false)
    }

    func testHeldLocalPreparationCancellationRetainsFlightAndDoesNotPublishConfirmation() async throws {
        let f = try await fixture(); try f.seedFavorites(); let flow = try await ledgerReady(f)
        f.localDisk.hold(.read)
        XCTAssertTrue(f.auth.prepareAccountRecoveryLocalFavorites(flow, configuration: f.configuration))
        await eventually { f.localDisk.isHeld }
        f.auth.cancelAccountRecoveryLocalFavorites(flow)
        XCTAssertTrue(flow.coordinator.hasPhysicalFlight)
        XCTAssertFalse(f.auth.prepareAccountRecoveryLocalFavorites(flow, configuration: f.configuration))
        XCTAssertNil(flow.coordinator.localFavoritesConfirmation)
        f.localDisk.release(); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.localFavoritesStatus, .cancelled)
        XCTAssertNil(flow.coordinator.localFavoritesConfirmation); try assertFavorites(f, removed: false)
        _ = try await localReady(f, flow)
        XCTAssertEqual(f.localFactoryCalls, 1)
    }

    func testChangedBytesAfterLocalConfirmationPreparationCannotBeDeleted() async throws {
        let f = try await fixture(); try f.seedFavorites(); let flow = try await ledgerReady(f)
        let confirmation = try await localReady(f, flow)
        let namespace = try XCTUnwrap(FavoritesContext.confirmed(userID: "reader-A").namespace)
        let changed = try FavoritesRecordCodec.encode(.empty, namespace: namespace)
        try changed.write(to: f.favoritesFile(namespace), options: .atomic)
        XCTAssertTrue(localConfirm(f, flow, confirmation))
        await eventually { flow.coordinator.localFavoritesStatus == .failed && !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(try Data(contentsOf: f.favoritesFile(namespace)), changed)
        XCTAssertEqual(f.localDisk.peek(namespace), f.localExpected[namespace]?.0)
        XCTAssertEqual(f.localDisk.deleteCount, 0); XCTAssertNil(flow.coordinator.localFavoritesReceipt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.favoritesDirectory.appendingPathComponent(namespace.recordBinding + ".cleanup.json").path))
        assertClosed(f)
    }

    func testCancellationDuringPendingWriteLeavesBothFormatsAndRetryUsesSameJournal() async throws {
        let f = try await fixture(); try f.seedFavorites(); let flow = try await ledgerReady(f)
        let confirmation = try await localReady(f, flow); f.localDisk.hold(.pending)
        XCTAssertTrue(localConfirm(f, flow, confirmation)); await eventually { f.localDisk.isHeld }
        f.auth.cancelAccountRecoveryLocalFavorites(flow)
        XCTAssertTrue(flow.coordinator.hasPhysicalFlight)
        f.localDisk.release(); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.localFavoritesStatus, .cancelled)
        try assertFavorites(f, removed: false)
        let next = try await localReady(f, flow)
        XCTAssertNotEqual(next, confirmation); XCTAssertEqual(f.localFactoryCalls, 1)
        XCTAssertTrue(localConfirm(f, flow, next)); await eventually { flow.coordinator.localFavoritesStatus == .removed }
        try assertFavorites(f, removed: true); XCTAssertEqual(f.requests.count, 2)
    }

    func testTimeoutDuringPhysicalRemovalRetainsSlotAndLateReceiptCannotPublishSuccess() async throws {
        let f = try await fixture(); try f.seedFavorites(); let flow = try await ledgerReady(f)
        let confirmation = try await localReady(f, flow); f.localDisk.hold(.remove)
        XCTAssertTrue(localConfirm(f, flow, confirmation)); await eventually { f.localDisk.isHeld }
        let timeout = try XCTUnwrap(f.timeouts.last); timeout()
        XCTAssertEqual(flow.coordinator.localFavoritesStatus, .failed)
        XCTAssertTrue(flow.coordinator.hasPhysicalFlight)
        XCTAssertFalse(f.auth.prepareAccountRecoveryLocalFavorites(flow, configuration: f.configuration))
        f.localDisk.release(); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.localFavoritesStatus, .failed); XCTAssertNil(flow.coordinator.localFavoritesReceipt)
        try assertFavorites(f, removed: true)
        let current = try await localReady(f, flow)
        XCTAssertTrue(localConfirm(f, flow, current)); await eventually { flow.coordinator.localFavoritesStatus == .removed }
        XCTAssertEqual(f.localDisk.deleteCount, 1); XCTAssertEqual(f.requests.count, 2)
    }

    func testAccountRoundTripDuringPhysicalRemovalRejectsOldReceiptAndPreservesOtherOwners() async throws {
        let f = try await fixture(); try f.seedFavorites(); let flow = try await ledgerReady(f)
        let confirmation = try await localReady(f, flow); f.localDisk.hold(.remove)
        XCTAssertTrue(localConfirm(f, flow, confirmation)); await eventually { f.localDisk.isHeld }
        f.observe("reader-B"); f.observe("reader-A")
        XCTAssertTrue(flow.coordinator.hasPhysicalFlight)
        XCTAssertFalse(localConfirm(f, flow, confirmation))
        f.localDisk.release(); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertNotEqual(flow.coordinator.localFavoritesStatus, .removed)
        XCTAssertNil(flow.coordinator.localFavoritesReceipt); try assertFavorites(f, removed: true)
        // The already-started recovery flow is conservatively retained across
        // account generations. Only a fresh process may reconcile this family.
        XCTAssertNil(f.prepare(try ticket(f)))
        XCTAssertEqual(f.requests.count, 2); XCTAssertEqual(f.localDisk.deleteCount, 1)
    }

    func testPartialRemovalFailureRequiresNewConfirmationAndPreservesOriginalPending() async throws {
        let f = try await fixture(); try f.seedFavorites(); let flow = try await ledgerReady(f)
        let confirmation = try await localReady(f, flow); f.localDisk.failLegacyOnce()
        XCTAssertTrue(localConfirm(f, flow, confirmation))
        await eventually { flow.coordinator.localFavoritesStatus == .failed && !flow.coordinator.hasPhysicalFlight }
        let namespace = try XCTUnwrap(FavoritesContext.confirmed(userID: "reader-A").namespace)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.favoritesFile(namespace).path))
        XCTAssertEqual(f.localDisk.peek(namespace), f.localExpected[namespace]?.0)
        XCTAssertNil(flow.coordinator.localFavoritesReceipt); XCTAssertFalse(localConfirm(f, flow, confirmation))
        let current = try await localReady(f, flow)
        XCTAssertTrue(localConfirm(f, flow, current)); await eventually { flow.coordinator.localFavoritesStatus == .removed }
        try assertFavorites(f, removed: true); XCTAssertEqual(f.requests.count, 2); XCTAssertEqual(f.localFactoryCalls, 1)
    }

    func testLocalPreparePublicationReentryCancelsBeforeFactoryAndDisk() async throws {
        let f = try await fixture(); try f.seedFavorites(); let flow = try await ledgerReady(f)
        var called = false
        let observation = flow.coordinator.objectWillChange.sink {
            guard !called, flow.coordinator.localFavoritesStatus == .preparing else { return }
            called = true; f.auth.cancelAccountRecoveryLocalFavorites(flow)
        }
        defer { observation.cancel() }
        XCTAssertFalse(f.auth.prepareAccountRecoveryLocalFavorites(flow, configuration: f.configuration))
        XCTAssertTrue(called); XCTAssertEqual(f.localFactoryCalls, 0); XCTAssertEqual(f.localDisk.readCount, 0)
        XCTAssertFalse(flow.coordinator.hasPhysicalFlight); try assertFavorites(f, removed: false)
    }

    func testLocalConfirmationPublicationReentryCancelsBeforePendingWrite() async throws {
        let f = try await fixture(); try f.seedFavorites(); let flow = try await ledgerReady(f)
        let confirmation = try await localReady(f, flow)
        var called = false
        let observation = flow.coordinator.objectWillChange.sink {
            guard !called, flow.coordinator.localFavoritesStatus == .removing else { return }
            called = true; f.auth.cancelAccountRecoveryLocalFavorites(flow)
        }
        defer { observation.cancel() }
        XCTAssertFalse(localConfirm(f, flow, confirmation))
        await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertTrue(called); XCTAssertNil(flow.coordinator.localFavoritesReceipt)
        try assertFavorites(f, removed: false)
    }

    func testLocalActionsRejectChangedConfigurationAndOldPreparedAccountGeneration() async throws {
        let f = try await fixture(); try f.seedFavorites(); let flow = try await ledgerReady(f)
        let other = try ReaderDeletionHTTPTransport.Configuration(projectID: "other-project", appID: f.configuration.appID,
            endpointURL: f.configuration.endpointURL)
        XCTAssertFalse(f.auth.prepareAccountRecoveryLocalFavorites(flow, configuration: other))
        XCTAssertEqual(f.localFactoryCalls, 0)
        let confirmation = try await localReady(f, flow)
        XCTAssertFalse(f.auth.confirmAccountRecoveryLocalFavorites(flow, confirmation: confirmation,
            configuration: other, userConfirmed: true))
        f.observe("reader-B"); f.observe("reader-A")
        XCTAssertFalse(localConfirm(f, flow, confirmation)); XCTAssertNil(flow.coordinator.localFavoritesReceipt)
        try assertFavorites(f, removed: false)
    }

    func testColdRestartAfterPartialRemovalReconcilesOriginalCloudFamilyBeforeNewLocalConfirmation() async throws {
        let f = try await fixture(); try f.seedFavorites(); let flow = try await ledgerReady(f)
        let confirmation = try await localReady(f, flow); f.localDisk.failLegacyOnce()
        XCTAssertTrue(localConfirm(f, flow, confirmation))
        await eventually { flow.coordinator.localFavoritesStatus == .failed && !flow.coordinator.hasPhysicalFlight }
        let restarted = try Fixture(restoring: f.root, localDisk: f.localDisk)
        restarted.localExpected = f.localExpected
        addTeardownBlock { @MainActor in await restarted.close() }
        if let task = restarted.launch() { await task.value }
        XCTAssertEqual(restarted.localFactoryCalls, 0); XCTAssertTrue(restarted.requests.isEmpty)
        XCTAssertFalse(restarted.auth.confirmAccountRecoveryLocalFavorites(flow, confirmation: confirmation,
            configuration: restarted.configuration, userConfirmed: true))
        let recovered = try await ledgerReady(restarted)
        XCTAssertEqual(recovered.ticket.checkpoint.marker, flow.ticket.checkpoint.marker)
        XCTAssertEqual(recovered.ticket.checkpoint.request, flow.ticket.checkpoint.request)
        XCTAssertEqual(restarted.requests.count, 2); XCTAssertEqual(restarted.localFactoryCalls, 0)
        let fresh = try await localReady(restarted, recovered)
        XCTAssertNotEqual(fresh, confirmation); XCTAssertTrue(localConfirm(restarted, recovered, fresh))
        await eventually { recovered.coordinator.localFavoritesStatus == .removed && !recovered.coordinator.hasPhysicalFlight }
        try assertFavorites(restarted, removed: true)
        XCTAssertFalse(recovered.coordinator.accountDeletionComplete)
        XCTAssertEqual(restarted.localDisk.deleteCount, 1)
    }

    func testBeforeReproductionIntroductionCleanupRetainsHistoryAndRejectsOldCloudEvents() async throws {
        let f = try Fixture(); addTeardownBlock { @MainActor in await f.close() }
        try await f.recovery.bootstrap()
        var bytes: [String: Data] = ["reading_history_v1": Data("unmarked-legacy".utf8)]
        var reads = 0, writes = 0, syncs = 0, profile = 0
        var timers: [@MainActor () -> Void] = []
        var callbacks: [@MainActor (ReadingHistoryRuntime.ExternalEvent) -> Void] = []
        let runtime = ReadingHistoryRuntime(disabled: false, transportFactory: {
            .init(storage: .init(read: { reads += 1; return bytes[$0.storageKey] },
                write: { namespace, data in writes += 1; bytes[namespace.storageKey] = data }),
                observe: { callbacks.append($0); return {} }, synchronize: { syncs += 1 })
        }, schedule: { _, callback in timers.append(callback); return {} },
            markProfileRead: { _, _ in profile += 1 }, recovery: f.recovery)
        runtime.prepareIfNeeded()
        for uid: String? in ["reader-B", nil, "reader-A"] {
            runtime.changeAccountContext(userID: uid)
            runtime.markRead(try XCTUnwrap(runtime.model.beginArticle(articleID: "article")))
        }
        let old = try XCTUnwrap(runtime.model.beginArticle(articleID: "pending"))
        XCTAssertEqual(runtime.model.saveProgress(0.4, ticket: old), .scheduled)
        let original = bytes
        _ = try await f.recovery.seal(binding: .init(ownerUID: "reader-A", epoch: 7))
        _ = try await f.recovery.recordDeletion(request: .init(expectedUID: "reader-A", membershipEpoch: 7), phase: .parent,
            configurationDigest: ReaderTransitionRecoveryStore.deletionConfigurationDigest(projectID: f.configuration.projectID, appID: f.configuration.appID, endpoint: f.configuration.endpointURL))
        if let task = f.launch() { await task.value }
        try f.seedFavorites(); try await seedResume(f); try seedPodcast(f); try f.introductionDisk.seed()
        let flow = try await podcastsRemoved(f), confirmation = try await introductionReady(f, flow)
        XCTAssertTrue(introductionConfirm(f, flow, confirmation)); await eventually { !flow.coordinator.hasPhysicalFlight }
        try assertIntroductionRemoved(f, flow)
        XCTAssertEqual(bytes, original)
        let oldCounts = [reads, writes, syncs, profile]
        timers.forEach { $0() }; callbacks.forEach { $0(.changed(keys: Set(bytes.keys))); $0(.accountChanged); $0(.quotaViolation) }
        runtime.markRead(old); runtime.flushAcceptedEdits(); runtime.prepareIfNeeded()
        runtime.changeAccountContext(userID: "reader-B"); runtime.changeAccountContext(userID: "reader-A")
        XCTAssertEqual(runtime.model.saveProgress(0.9, ticket: old), .stale)
        XCTAssertEqual([reads, writes, syncs, profile], oldCounts); XCTAssertEqual(bytes, original)
        XCTAssertNil(runtime.model.beginArticle(articleID: "new")); XCTAssertFalse(flow.coordinator.accountDeletionComplete)
        assertClosed(f)
    }

    func testBeforeReproductionPodcastCleanupRetainsIntroductionDraftAndCompletion() async throws {
        let f = try Fixture(); addTeardownBlock { @MainActor in await f.close() }
        try await f.recovery.bootstrap()
        var bytes: Data?, guestBytes: Data?, reads = 0, writes = 0
        let canonical = CanonicalSessionState()
        _ = canonical.adopt(.init(uid: "reader-A", email: "original@example.invalid", isEmailVerified: true))
        let intro = ReaderIntroductionModel(storage: .init(read: { reads += 1; return bytes }, write: { writes += 1; bytes = $0 }), recovery: f.recovery)
        XCTAssertTrue(intro.bindContext(canonical.contextTicket(), isCurrent: canonical.isCurrent))
        XCTAssertTrue(intro.start()); XCTAssertTrue(intro.complete()); XCTAssertTrue(intro.replay())
        XCTAssertTrue(intro.setSelectedTopicIDs(["film", "music"]))
        let guest = GuestReaderInterestsModel(storage: .init(read: { guestBytes }, write: { guestBytes = $0 }))
        let guestState = CanonicalSessionState(); _ = guestState.adopt(nil)
        XCTAssertTrue(guest.start())
        XCTAssertTrue(guest.save(["guest-topic"], context: guestState.contextTicket(), isCurrent: guestState.isCurrent))
        let original = bytes, originalGuest = guestBytes, originalWrites = writes
        _ = try await f.recovery.seal(binding: .init(ownerUID: "reader-A", epoch: 7))
        _ = try await f.recovery.recordDeletion(request: .init(expectedUID: "reader-A", membershipEpoch: 7), phase: .parent,
            configurationDigest: ReaderTransitionRecoveryStore.deletionConfigurationDigest(projectID: f.configuration.projectID, appID: f.configuration.appID, endpoint: f.configuration.endpointURL))
        if let task = f.launch() { await task.value }
        try f.seedFavorites(); try await seedResume(f); try seedPodcast(f)
        let flow = try await resumesRemoved(f), confirmation = try await podcastReady(f, flow)
        XCTAssertTrue(podcastConfirm(f, flow, confirmation))
        await eventually { flow.coordinator.localPodcastStatus == .removed && !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(bytes, original); XCTAssertEqual(guestBytes, originalGuest)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(bytes)) as? [String: Any])
        XCTAssertEqual(json["completed"] as? Bool, true)
        XCTAssertEqual(json["selectedTopicIDs"] as? [String], ["film", "music"])
        let closedReads = reads
        XCTAssertFalse(intro.toggleTopic("old")); XCTAssertFalse(intro.replay()); XCTAssertFalse(intro.retry())
        XCTAssertEqual(reads, closedReads); XCTAssertEqual(writes, originalWrites); XCTAssertFalse(intro.isPresented)
        XCTAssertFalse(flow.coordinator.accountDeletionComplete); assertClosed(f)
    }

    func testBeforeReproductionResumeCleanupRetainsPodcastOwnersWhilePlayerStaysClosed() async throws {
        let f = try Fixture(); addTeardownBlock { @MainActor in await f.close() }
        try await f.recovery.bootstrap()
        var bytes: [String: Data] = ["podcast_progress_v1": Data("unowned-legacy".utf8)]
        var writes = 0, effects: [String] = []
        let runtime = PodcastProgressRuntime(disabled: false, storageFactory: {
            .init(read: { bytes[$0.storageKey] }, write: { namespace, data in
                writes += 1; bytes[namespace.storageKey] = data
            })
        }, recovery: f.recovery)
        let player = PodcastPlaybackSessionCoordinator(store: runtime.model, effects: .init(
            cancelCallbacks: { effects.append("cancel") }, stopPlayback: { effects.append("stop") },
            clearPresentation: { effects.append("presentation") }, clearNowPlaying: { effects.append("nowPlaying") },
            deactivateAudio: { effects.append("deactivate") }))
        runtime.model.onContextInvalidated = { [weak player] in player?.contextInvalidated() }
        runtime.prepareIfNeeded()
        for uid: String? in ["reader-A", "reader-B", nil] {
            runtime.changeAccountContext(userID: uid)
            let session = try XCTUnwrap(player.beginSession(episodeID: "episode", articleID: "article"))
            XCTAssertTrue(player.save(session.ticket, seconds: 42, duration: 600))
        }
        runtime.changeAccountContext(userID: "reader-A")
        let original = try XCTUnwrap(player.beginSession(episodeID: "episode", articleID: "article"))
        let before = bytes, beforeWrites = writes, beforeEffects = effects.count
        _ = try await f.recovery.seal(binding: .init(ownerUID: "reader-A", epoch: 7))
        _ = try await f.recovery.recordDeletion(request: .init(expectedUID: "reader-A", membershipEpoch: 7), phase: .parent,
            configurationDigest: ReaderTransitionRecoveryStore.deletionConfigurationDigest(
                projectID: f.configuration.projectID, appID: f.configuration.appID, endpoint: f.configuration.endpointURL))
        if let task = f.launch() { await task.value }
        try await seedResume(f)
        let flow = try await favoritesRemoved(f), confirmation = try await resumeReady(f, flow)
        XCTAssertTrue(resumeConfirm(f, flow, confirmation))
        await eventually { flow.coordinator.localResumeStatus == .removed && !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(bytes, before, "Current recovery phases retain every podcast partition, including original A")
        XCTAssertFalse(player.save(original.ticket, seconds: 90, duration: 600))
        XCTAssertFalse(player.complete(original.ticket))
        XCTAssertFalse(player.isCurrent(original.ticket)); XCTAssertFalse(runtime.model.hasPlaybackAccess)
        XCTAssertEqual(writes, beforeWrites)
        XCTAssertEqual(Array(effects.dropFirst(beforeEffects)), ["cancel", "stop", "presentation", "nowPlaying", "deactivate"])
        XCTAssertFalse(flow.coordinator.accountDeletionComplete); assertClosed(f)
    }

    func testBeforeReproductionFavoriteCleanupRetainsResumeOwnersWhileControllerStaysClosed() async throws {
        let f = try await fixture(); try f.seedFavorites()
        let source = try XCTUnwrap(ReaderResumeIdentity(articleID: "original", sourceRevision: "r1", html: "<p>Original article</p>"))
        let anchor = ReaderResumeAnchor(index: 4, fingerprint: "12345678")
        for owner in [ReadingHistoryContext.confirmed(userID: "reader-A").namespace!.recordBinding,
                      ReadingHistoryContext.confirmed(userID: "reader-B").namespace!.recordBinding, "guest"] {
            try await f.resumeStore.save(owner: owner, source: source, anchor: anchor)
        }
        let original = f.resumeDisk.peek()
        let flow = try await ledgerReady(f)
        let confirmation = try await localReady(f, flow)
        XCTAssertTrue(localConfirm(f, flow, confirmation))
        await eventually { flow.coordinator.localFavoritesStatus == .removed && !flow.coordinator.hasPhysicalFlight }
        try assertFavorites(f, removed: true)
        XCTAssertEqual(f.resumeDisk.peek(), original)
        XCTAssertEqual(try ReaderResumeRecord.decode(f.resumeDisk.peek()).entries.count, 3)
        let controller = ReaderResumeController(store: f.resumeStore, legacyAdmission: f.recovery.admission)
        let reads = f.resumeDisk.readCount
        controller.bind(owner: ReadingHistoryContext.confirmed(userID: "reader-A").namespace!.recordBinding,
                        source: source, sessionID: UUID(), documentID: UUID().uuidString, isCurrent: { true })
        await Task.yield()
        XCTAssertNil(controller.snapshot.offer); XCTAssertEqual(f.resumeDisk.readCount, reads)
        XCTAssertFalse(flow.coordinator.accountDeletionComplete); assertClosed(f)
    }

    private func seedResume(_ f: Fixture) async throws {
        let source = try XCTUnwrap(ReaderResumeIdentity(articleID: "original", sourceRevision: "r1", html: "<p>Original</p>"))
        for owner in [ReadingHistoryContext.confirmed(userID: "reader-A").namespace!.recordBinding,
                      ReadingHistoryContext.confirmed(userID: "reader-B").namespace!.recordBinding, "guest"] {
            try await f.resumeStore.save(owner: owner, source: source, anchor: .init(index: 4, fingerprint: "12345678"))
        }
    }
    private func favoritesRemoved(_ f: Fixture) async throws -> Flow {
        let flow = try await ledgerReady(f)
        let confirmation = try await localReady(f, flow)
        XCTAssertTrue(localConfirm(f, flow, confirmation))
        await eventually { flow.coordinator.localFavoritesStatus == .removed && !flow.coordinator.hasPhysicalFlight }
        return flow
    }
    private func resumeReady(_ f: Fixture, _ flow: Flow) async throws -> Model.LocalResumeConfirmation {
        XCTAssertTrue(f.auth.prepareAccountRecoveryLocalResume(flow, configuration: f.configuration))
        await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.localResumeStatus, .ready)
        return try XCTUnwrap(flow.coordinator.localResumeConfirmation)
    }
    private func resumeConfirm(_ f: Fixture, _ flow: Flow, _ confirmation: Model.LocalResumeConfirmation) -> Bool {
        f.auth.confirmAccountRecoveryLocalResume(flow, confirmation: confirmation,
            configuration: f.configuration, userConfirmed: true)
    }
    private func assertResume(_ f: Fixture, removed: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        let entries = try ReaderResumeRecord.decode(f.resumeDisk.peek()).entries
        let ownerA = ReadingHistoryContext.confirmed(userID: "reader-A").namespace!.recordBinding
        let ownerB = ReadingHistoryContext.confirmed(userID: "reader-B").namespace!.recordBinding
        XCTAssertEqual(entries.filter { $0.owner == ownerA }.count, removed ? 0 : 1, file: file, line: line)
        XCTAssertEqual(entries.filter { $0.owner == ownerB }.count, 1, file: file, line: line)
        XCTAssertEqual(entries.filter { $0.owner == "guest" }.count, 1, file: file, line: line)
        for entry in entries { XCTAssertEqual(entry.anchor, .init(index: 4, fingerprint: "12345678"), file: file, line: line) }
        assertClosed(f)
    }

    func testResumeCleanupNeedsSeparateConfirmationAfterFavoritesAndReadback() async throws {
        let f = try await fixture(); try f.seedFavorites(); try await seedResume(f)
        let flow = try await ledgerReady(f)
        XCTAssertFalse(f.auth.prepareAccountRecoveryLocalResume(flow, configuration: f.configuration))
        let favorite = try await localReady(f, flow)
        XCTAssertTrue(localConfirm(f, flow, favorite))
        await eventually { flow.coordinator.localFavoritesStatus == .removed }
        let reads = f.resumeDisk.readCount, writes = f.resumeDisk.writeCount
        for _ in 0..<100 {
            XCTAssertTrue(flow.coordinator.canPrepareLocalResumeCleanup)
            XCTAssertNil(flow.coordinator.localResumeConfirmation); XCTAssertNil(flow.coordinator.localResumeMessage)
        }
        XCTAssertEqual(f.resumeDisk.readCount, reads); XCTAssertEqual(f.resumeDisk.writeCount, writes)
        let confirmation = try await resumeReady(f, flow)
        XCTAssertFalse(f.auth.confirmAccountRecoveryLocalResume(flow, confirmation: confirmation,
            configuration: f.configuration, userConfirmed: false))
        try assertResume(f, removed: false)
        XCTAssertTrue(resumeConfirm(f, flow, confirmation)); XCTAssertFalse(resumeConfirm(f, flow, confirmation))
        await eventually { flow.coordinator.localResumeStatus == .removed && !flow.coordinator.hasPhysicalFlight }
        try assertResume(f, removed: true)
        XCTAssertEqual(flow.coordinator.localResumeReceipt?.owner,
            ReadingHistoryContext.confirmed(userID: "reader-A").namespace?.recordBinding)
        XCTAssertTrue(flow.coordinator.localResumeReceipt?.belongs(to: try XCTUnwrap(f.recovery.deletionCheckpoint)) == true)
        XCTAssertFalse(flow.coordinator.accountDeletionComplete); XCTAssertEqual(f.requests.count, 2)
        XCTAssertFalse(flow.coordinator.canPrepareLocalResumeCleanup)
    }

    func testResumeCancellationConsumesPreparedConfirmationWithoutWrites() async throws {
        let f = try await fixture(); try f.seedFavorites(); try await seedResume(f); let flow = try await favoritesRemoved(f)
        let old = try await resumeReady(f, flow); let writes = f.resumeDisk.writeCount
        f.auth.cancelAccountRecoveryLocalResume(flow)
        XCTAssertEqual(flow.coordinator.localResumeStatus, .cancelled)
        XCTAssertFalse(resumeConfirm(f, flow, old)); XCTAssertEqual(f.resumeDisk.writeCount, writes)
        let fresh = try await resumeReady(f, flow); XCTAssertNotEqual(fresh, old)
        XCTAssertFalse(resumeConfirm(f, flow, old)); XCTAssertTrue(resumeConfirm(f, flow, fresh))
        await eventually { flow.coordinator.localResumeStatus == .removed }; try assertResume(f, removed: true)
    }

    func testResumePreparationPublicationReentryPreventsStorageRead() async throws {
        let f = try await fixture(); try f.seedFavorites(); try await seedResume(f); let flow = try await favoritesRemoved(f)
        let reads = f.resumeDisk.readCount
        let observation = flow.coordinator.objectWillChange.sink {
            if flow.coordinator.localResumeStatus == .preparing { f.auth.cancelAccountRecoveryLocalResume(flow) }
        }
        defer { observation.cancel() }
        XCTAssertFalse(f.auth.prepareAccountRecoveryLocalResume(flow, configuration: f.configuration))
        XCTAssertEqual(f.resumeDisk.readCount, reads); XCTAssertFalse(flow.coordinator.hasPhysicalFlight)
        try assertResume(f, removed: false)
    }

    func testResumeRemovalPublicationReentryPreventsPendingWrite() async throws {
        let f = try await fixture(); try f.seedFavorites(); try await seedResume(f); let flow = try await favoritesRemoved(f)
        let confirmation = try await resumeReady(f, flow), writes = f.resumeDisk.writeCount
        let observation = flow.coordinator.objectWillChange.sink {
            if flow.coordinator.localResumeStatus == .removing { f.auth.cancelAccountRecoveryLocalResume(flow) }
        }
        defer { observation.cancel() }
        XCTAssertFalse(resumeConfirm(f, flow, confirmation))
        XCTAssertEqual(f.resumeDisk.writeCount, writes); XCTAssertFalse(flow.coordinator.hasPhysicalFlight)
        try assertResume(f, removed: false)
    }

    func testResumeChangedRecordNeedsFreshExplicitConfirmation() async throws {
        let f = try await fixture(); try f.seedFavorites(); try await seedResume(f); let flow = try await favoritesRemoved(f)
        let confirmation = try await resumeReady(f, flow)
        var envelope = try ReaderResumeRecord.decode(f.resumeDisk.peek()); envelope.entries.reverse()
        let changed = try ReaderResumeRecord.encode(envelope); f.resumeDisk.replace(changed)
        XCTAssertTrue(resumeConfirm(f, flow, confirmation)); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.localResumeStatus, .failed); XCTAssertEqual(f.resumeDisk.peek(), changed)
        XCTAssertNil(flow.coordinator.localResumeReceipt)
        let fresh = try await resumeReady(f, flow); XCTAssertTrue(resumeConfirm(f, flow, fresh))
        await eventually { flow.coordinator.localResumeStatus == .removed }; try assertResume(f, removed: true)
    }

    func testResumeCancellationDuringPendingWriteRetainsPhysicalFlight() async throws {
        let f = try await fixture(); try f.seedFavorites(); try await seedResume(f); let flow = try await favoritesRemoved(f)
        let confirmation = try await resumeReady(f, flow); f.resumeDisk.holdWrite()
        XCTAssertTrue(resumeConfirm(f, flow, confirmation)); await eventually { f.resumeDisk.isHeld }
        f.auth.cancelAccountRecoveryLocalResume(flow)
        XCTAssertTrue(flow.coordinator.hasPhysicalFlight)
        XCTAssertFalse(f.auth.prepareAccountRecoveryLocalResume(flow, configuration: f.configuration))
        f.resumeDisk.release(); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.localResumeStatus, .cancelled); XCTAssertNil(flow.coordinator.localResumeReceipt)
        try assertResume(f, removed: false)
        let fresh = try await resumeReady(f, flow); XCTAssertTrue(resumeConfirm(f, flow, fresh))
        await eventually { flow.coordinator.localResumeStatus == .removed }; try assertResume(f, removed: true)
    }

    func testResumeTimeoutDuringFinalWriteCannotPublishLateSuccess() async throws {
        let f = try await fixture(); try f.seedFavorites(); try await seedResume(f); let flow = try await favoritesRemoved(f)
        let confirmation = try await resumeReady(f, flow); f.resumeDisk.holdWrite(after: 2)
        XCTAssertTrue(resumeConfirm(f, flow, confirmation)); await eventually { f.resumeDisk.isHeld }
        try XCTUnwrap(f.timeouts.last)()
        XCTAssertEqual(flow.coordinator.localResumeStatus, .failed); XCTAssertTrue(flow.coordinator.hasPhysicalFlight)
        XCTAssertFalse(f.auth.prepareAccountRecoveryLocalResume(flow, configuration: f.configuration))
        f.resumeDisk.release(); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.localResumeStatus, .failed); XCTAssertNil(flow.coordinator.localResumeReceipt)
        try assertResume(f, removed: true)
        let fresh = try await resumeReady(f, flow); XCTAssertTrue(resumeConfirm(f, flow, fresh))
        await eventually { flow.coordinator.localResumeStatus == .removed }; XCTAssertEqual(f.requests.count, 2)
    }

    func testResumeAccountRoundTripDuringFinalWriteRejectsLateReceipt() async throws {
        let f = try await fixture(); try f.seedFavorites(); try await seedResume(f); let flow = try await favoritesRemoved(f)
        let confirmation = try await resumeReady(f, flow); f.resumeDisk.holdWrite(after: 2)
        XCTAssertTrue(resumeConfirm(f, flow, confirmation)); await eventually { f.resumeDisk.isHeld }
        f.observe("reader-B"); f.observe("reader-A")
        XCTAssertTrue(flow.coordinator.hasPhysicalFlight)
        XCTAssertFalse(resumeConfirm(f, flow, confirmation))
        f.resumeDisk.release(); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertNotEqual(flow.coordinator.localResumeStatus, .removed); XCTAssertNil(flow.coordinator.localResumeReceipt)
        try assertResume(f, removed: true); XCTAssertEqual(f.requests.count, 2)
    }

    func testResumeFailedFinalWritePreservesPendingAndRetriesSameOriginal() async throws {
        let f = try await fixture(); try f.seedFavorites(); try await seedResume(f); let flow = try await favoritesRemoved(f)
        let confirmation = try await resumeReady(f, flow); f.resumeDisk.failWrite(after: 2)
        XCTAssertTrue(resumeConfirm(f, flow, confirmation)); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.localResumeStatus, .failed); try assertResume(f, removed: false)
        let fresh = try await resumeReady(f, flow); XCTAssertTrue(resumeConfirm(f, flow, fresh))
        await eventually { flow.coordinator.localResumeStatus == .removed }; try assertResume(f, removed: true)
    }

    func testResumeLogicalRestartReconcilesPendingWithoutImplicitCleanup() async throws {
        let f = try await fixture(); try f.seedFavorites(); try await seedResume(f); let flow = try await favoritesRemoved(f)
        let confirmation = try await resumeReady(f, flow); f.resumeDisk.failWrite(after: 2)
        XCTAssertTrue(resumeConfirm(f, flow, confirmation)); await eventually { !flow.coordinator.hasPhysicalFlight }
        let original = f.resumeDisk.peek(), writes = f.resumeDisk.writeCount
        let restarted = try Fixture(restoring: f.root, localDisk: f.localDisk, resumeDisk: f.resumeDisk)
        restarted.localExpected = f.localExpected
        addTeardownBlock { @MainActor in await restarted.close() }
        if let task = restarted.launch() { await task.value }
        XCTAssertEqual(f.resumeDisk.peek(), original); XCTAssertEqual(f.resumeDisk.writeCount, writes)
        let recovered = try await favoritesRemoved(restarted)
        XCTAssertEqual(f.resumeDisk.peek(), original)
        XCTAssertFalse(restarted.auth.confirmAccountRecoveryLocalResume(flow, confirmation: confirmation,
            configuration: restarted.configuration, userConfirmed: true))
        let fresh = try await resumeReady(restarted, recovered)
        XCTAssertNotEqual(fresh, confirmation); XCTAssertTrue(resumeConfirm(restarted, recovered, fresh))
        await eventually { recovered.coordinator.localResumeStatus == .removed }; try assertResume(restarted, removed: true)
        XCTAssertFalse(recovered.coordinator.accountDeletionComplete)
    }

    func testResumeChangedConfigurationCannotAcquireOrCommitOldConfirmation() async throws {
        let f = try await fixture(); try f.seedFavorites(); try await seedResume(f); let flow = try await favoritesRemoved(f)
        let other = try ReaderDeletionHTTPTransport.Configuration(projectID: "other-project", appID: f.configuration.appID,
            endpointURL: f.configuration.endpointURL)
        XCTAssertFalse(f.auth.prepareAccountRecoveryLocalResume(flow, configuration: other))
        let confirmation = try await resumeReady(f, flow)
        XCTAssertFalse(f.auth.confirmAccountRecoveryLocalResume(flow, confirmation: confirmation,
            configuration: other, userConfirmed: true)); try assertResume(f, removed: false)
    }

    func testResumeMissingInjectedStoreStaysInertAfterFavorites() async throws {
        let f = try await fixture(); f.includeResumeStore = false
        try f.seedFavorites(); try await seedResume(f); let flow = try await favoritesRemoved(f)
        let reads = f.resumeDisk.readCount
        XCTAssertFalse(flow.coordinator.canPrepareLocalResumeCleanup)
        XCTAssertFalse(f.auth.prepareAccountRecoveryLocalResume(flow, configuration: f.configuration))
        XCTAssertEqual(f.resumeDisk.readCount, reads); XCTAssertNil(flow.coordinator.localResumeReceipt)
        try assertResume(f, removed: false)
    }

    private func podcastNamespace(_ uid: String?) throws -> PodcastProgressNamespace {
        try XCTUnwrap(PodcastProgressContext.confirmed(userID: uid).namespace)
    }
    private func seedPodcast(_ f: Fixture) throws {
        for uid: String? in ["reader-A", "reader-B", nil] {
            let namespace = try podcastNamespace(uid)
            let record = PodcastProgressRecord(entries: [.init(episodeID: "episode", articleID: "article", positionSeconds: 42, durationSeconds: 600)], lastEpisodeID: "episode")
            f.podcastDisk.records[namespace.storageKey] = try PodcastProgressRecordCodec.encode(record, namespace: namespace)
        }
        f.podcastDisk.records["podcast_progress_v1"] = Data("unowned-legacy".utf8)
    }
    private func resumesRemoved(_ f: Fixture) async throws -> Flow {
        let flow = try await favoritesRemoved(f), confirmation = try await resumeReady(f, flow)
        XCTAssertTrue(resumeConfirm(f, flow, confirmation))
        await eventually { flow.coordinator.localResumeStatus == .removed && !flow.coordinator.hasPhysicalFlight }
        return flow
    }
    private func podcastFixture() async throws -> (Fixture, Flow) {
        let f = try await fixture(); try f.seedFavorites(); try await seedResume(f); try seedPodcast(f)
        return (f, try await resumesRemoved(f))
    }
    private func podcastReady(_ f: Fixture, _ flow: Flow) async throws -> Model.LocalPodcastConfirmation {
        XCTAssertTrue(f.auth.prepareAccountRecoveryLocalPodcast(flow, configuration: f.configuration))
        await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.localPodcastStatus, .ready)
        return try XCTUnwrap(flow.coordinator.localPodcastConfirmation)
    }
    @discardableResult private func podcastConfirm(_ f: Fixture, _ flow: Flow, _ confirmation: Model.LocalPodcastConfirmation, userConfirmed: Bool = true) -> Bool {
        f.auth.confirmAccountRecoveryLocalPodcast(flow, confirmation: confirmation, configuration: f.configuration, userConfirmed: userConfirmed)
    }
    private func assertPodcast(_ f: Fixture, original: [String: Data], removed: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        let owner = try podcastNamespace("reader-A")
        for (key, value) in original where key != owner.storageKey { XCTAssertEqual(f.podcastDisk.records[key], value, file: file, line: line) }
        XCTAssertEqual(Set(f.podcastDisk.records.keys), Set(original.keys), file: file, line: line)
        let data = try XCTUnwrap(f.podcastDisk.records[owner.storageKey])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((json["entries"] as? [Any])?.count, removed ? 0 : 1, file: file, line: line)
        if removed { XCTAssertNil(json["lastEpisodeID"] as? String, file: file, line: line) }
        assertClosed(f, file: file, line: line)
    }

    func testPodcastCleanupNeedsSeparateSingleUseConfirmationAndPreservesOtherPartitions() async throws {
        let (f, flow) = try await podcastFixture(), original = f.podcastDisk.records
        XCTAssertEqual(f.podcastDisk.factories, 0); XCTAssertEqual(f.podcastDisk.reads, 0)
        for _ in 0..<100 { XCTAssertTrue(flow.coordinator.canPrepareLocalPodcastCleanup); _ = flow.coordinator.localPodcastMessage }
        XCTAssertEqual(f.podcastDisk.factories, 0)
        let confirmation = try await podcastReady(f, flow)
        XCTAssertEqual(f.podcastDisk.records, original); XCTAssertEqual(f.podcastDisk.writes, 0)
        XCTAssertFalse(podcastConfirm(f, flow, confirmation, userConfirmed: false))
        f.auth.cancelAccountRecoveryLocalPodcast(flow)
        XCTAssertFalse(podcastConfirm(f, flow, confirmation)); XCTAssertEqual(f.podcastDisk.writes, 0)
        let fresh = try await podcastReady(f, flow); XCTAssertNotEqual(fresh, confirmation)
        XCTAssertTrue(podcastConfirm(f, flow, fresh)); XCTAssertFalse(podcastConfirm(f, flow, fresh))
        await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.localPodcastStatus, .removed)
        XCTAssertTrue(try XCTUnwrap(flow.coordinator.localPodcastReceipt).isComplete)
        try assertPodcast(f, original: original, removed: true)
        let reads = f.podcastDisk.reads, writes = f.podcastDisk.writes
        f.podcastRuntime.prepareIfNeeded(); f.podcastRuntime.changeAccountContext(userID: "reader-A")
        f.podcastRuntime.model.retryStorage()
        XCTAssertNil(f.podcastRuntime.model.beginSession(episodeID: "new", articleID: nil))
        XCTAssertEqual(f.podcastDisk.reads, reads); XCTAssertEqual(f.podcastDisk.writes, writes)
        XCTAssertFalse(flow.coordinator.accountDeletionComplete); XCTAssertEqual(f.requests.count, 2)
    }

    func testPodcastCleanupRequiresCompletedEarlierPhasesAndExplicitStore() async throws {
        let f = try await fixture(); try f.seedFavorites(); try await seedResume(f); try seedPodcast(f)
        f.includePodcastStore = false
        let flow = try await ledgerReady(f)
        XCTAssertFalse(f.auth.prepareAccountRecoveryLocalPodcast(flow, configuration: f.configuration))
        let favorite = try await localReady(f, flow); XCTAssertTrue(localConfirm(f, flow, favorite))
        await eventually { flow.coordinator.localFavoritesStatus == .removed }
        XCTAssertFalse(f.auth.prepareAccountRecoveryLocalPodcast(flow, configuration: f.configuration))
        let resume = try await resumeReady(f, flow); XCTAssertTrue(resumeConfirm(f, flow, resume))
        await eventually { flow.coordinator.localResumeStatus == .removed }
        XCTAssertFalse(f.auth.prepareAccountRecoveryLocalPodcast(flow, configuration: f.configuration))
        XCTAssertEqual(f.podcastDisk.factories, 0); XCTAssertEqual(f.podcastDisk.writes, 0)
    }

    func testPodcastPreparationPublicationAccountRoundTripDoesNotOpenStorage() async throws {
        let (f, flow) = try await podcastFixture()
        let observation = flow.coordinator.objectWillChange.sink { @MainActor in
            if flow.coordinator.localPodcastStatus == .preparing { f.observe("reader-B"); f.observe("reader-A") }
        }
        defer { observation.cancel() }
        XCTAssertFalse(f.auth.prepareAccountRecoveryLocalPodcast(flow, configuration: f.configuration))
        XCTAssertEqual(f.podcastDisk.factories, 0); XCTAssertEqual(f.podcastDisk.reads, 0)
        XCTAssertNil(flow.coordinator.localPodcastConfirmation)
    }

    func testPodcastFactoryAccountRoundTripRejectsReturnedStorageBeforeRead() async throws {
        let (f, flow) = try await podcastFixture()
        f.podcastDisk.onFactory = { f.observe("reader-B"); f.observe("reader-A") }
        XCTAssertTrue(f.auth.prepareAccountRecoveryLocalPodcast(flow, configuration: f.configuration))
        await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(f.podcastDisk.factories, 1); XCTAssertEqual(f.podcastDisk.reads, 0)
        XCTAssertNil(flow.coordinator.localPodcastConfirmation); XCTAssertEqual(f.podcastDisk.writes, 0)
        f.podcastDisk.onFactory = nil
    }

    func testPodcastChangedBytesAfterConfirmationAreNotRemoved() async throws {
        let (f, flow) = try await podcastFixture(), confirmation = try await podcastReady(f, flow)
        let namespace = try podcastNamespace("reader-A")
        let changed = try PodcastProgressRecordCodec.encode(.init(entries: [.init(episodeID: "new", articleID: nil, positionSeconds: 80, durationSeconds: 600)], lastEpisodeID: "new"), namespace: namespace)
        f.podcastDisk.records[namespace.storageKey] = changed
        XCTAssertTrue(podcastConfirm(f, flow, confirmation)); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.localPodcastStatus, .failed); XCTAssertEqual(f.podcastDisk.records[namespace.storageKey], changed)
        XCTAssertEqual(f.podcastDisk.writes, 0); XCTAssertNil(flow.coordinator.localPodcastReceipt)
    }

    func testPodcastAccountRoundTripInsideCommitReadStopsBeforeAnyWrite() async throws {
        let (f, flow) = try await podcastFixture(), original = f.podcastDisk.records
        let confirmation = try await podcastReady(f, flow)
        f.podcastDisk.onRead = {
            f.podcastDisk.onRead = nil; f.observe("reader-B"); f.observe("reader-A")
            XCTAssertFalse(f.podcastRuntime.model.isPhysicallyIdle)
        }
        XCTAssertTrue(podcastConfirm(f, flow, confirmation)); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(f.podcastDisk.records, original); XCTAssertEqual(f.podcastDisk.writes, 0)
        XCTAssertNil(flow.coordinator.localPodcastReceipt); XCTAssertNotEqual(flow.coordinator.localPodcastStatus, .removed)
    }

    func testPodcastCancellationInsidePendingWriteRetainsPhysicalGuardAndNeedsFreshConfirmation() async throws {
        let (f, flow) = try await podcastFixture(), original = f.podcastDisk.records
        let confirmation = try await podcastReady(f, flow)
        f.podcastDisk.onWrite = {
            f.podcastDisk.onWrite = nil
            XCTAssertFalse(f.podcastRuntime.model.isPhysicallyIdle)
            f.auth.cancelAccountRecoveryLocalPodcast(flow)
            XCTAssertTrue(flow.coordinator.hasPhysicalFlight)
            XCTAssertFalse(f.auth.prepareAccountRecoveryLocalPodcast(flow, configuration: f.configuration))
        }
        XCTAssertTrue(podcastConfirm(f, flow, confirmation)); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.localPodcastStatus, .cancelled); XCTAssertNil(flow.coordinator.localPodcastReceipt)
        try assertPodcast(f, original: original, removed: false)
        let fresh = try await podcastReady(f, flow); XCTAssertTrue(podcastConfirm(f, flow, fresh))
        await eventually { flow.coordinator.localPodcastStatus == .removed }; try assertPodcast(f, original: original, removed: true)
    }

    func testPodcastTimeoutInsideCompletedWriteRejectsLateSuccessThenReadbackRetryWorks() async throws {
        let (f, flow) = try await podcastFixture(), original = f.podcastDisk.records
        let confirmation = try await podcastReady(f, flow), baseline = f.podcastDisk.writes
        f.podcastDisk.onWrite = {
            guard f.podcastDisk.writes == baseline + 2 else { return }
            f.podcastDisk.onWrite = nil; f.timeouts.last?()
            XCTAssertFalse(f.podcastRuntime.model.isPhysicallyIdle); XCTAssertTrue(flow.coordinator.hasPhysicalFlight)
        }
        XCTAssertTrue(podcastConfirm(f, flow, confirmation)); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.localPodcastStatus, .failed); XCTAssertNil(flow.coordinator.localPodcastReceipt)
        try assertPodcast(f, original: original, removed: true)
        let fresh = try await podcastReady(f, flow); XCTAssertTrue(podcastConfirm(f, flow, fresh))
        await eventually { flow.coordinator.localPodcastStatus == .removed }; XCTAssertEqual(f.requests.count, 2)
    }

    func testPodcastAccountRoundTripInsideFinalWriteCannotPublishOldReceipt() async throws {
        let (f, flow) = try await podcastFixture(), original = f.podcastDisk.records
        let confirmation = try await podcastReady(f, flow), baseline = f.podcastDisk.writes
        f.podcastDisk.onWrite = {
            guard f.podcastDisk.writes == baseline + 2 else { return }
            f.podcastDisk.onWrite = nil; f.observe("reader-B"); f.observe("reader-A")
            XCTAssertFalse(f.podcastRuntime.model.isPhysicallyIdle); XCTAssertTrue(flow.coordinator.hasPhysicalFlight)
        }
        XCTAssertTrue(podcastConfirm(f, flow, confirmation)); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertNotEqual(flow.coordinator.localPodcastStatus, .removed); XCTAssertNil(flow.coordinator.localPodcastReceipt)
        XCTAssertFalse(f.auth.prepareAccountRecoveryLocalPodcast(flow, configuration: f.configuration))
        try assertPodcast(f, original: original, removed: true)
    }

    func testPodcastFailedFinalWriteReconcilesAfterLogicalObjectRestart() async throws {
        let (f, flow) = try await podcastFixture(), original = f.podcastDisk.records
        let confirmation = try await podcastReady(f, flow); f.podcastDisk.failWriteAt = f.podcastDisk.writes + 2
        XCTAssertTrue(podcastConfirm(f, flow, confirmation)); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.localPodcastStatus, .failed); try assertPodcast(f, original: original, removed: false)
        let writes = f.podcastDisk.writes
        let restarted = try Fixture(restoring: f.root, localDisk: f.localDisk, resumeDisk: f.resumeDisk, podcastDisk: f.podcastDisk)
        restarted.localExpected = f.localExpected; addTeardownBlock { @MainActor in await restarted.close() }
        if let task = restarted.launch() { await task.value }
        let recovered = try await resumesRemoved(restarted)
        XCTAssertEqual(f.podcastDisk.writes, writes, "Reconstruction and earlier phases cannot silently purge podcast data")
        let fresh = try await podcastReady(restarted, recovered)
        XCTAssertNotEqual(fresh, confirmation); XCTAssertTrue(podcastConfirm(restarted, recovered, fresh))
        await eventually { recovered.coordinator.localPodcastStatus == .removed }
        try assertPodcast(restarted, original: original, removed: true); XCTAssertFalse(recovered.coordinator.accountDeletionComplete)
    }

    func testPodcastChangedConfigurationCannotUsePreparedConfirmation() async throws {
        let (f, flow) = try await podcastFixture(), confirmation = try await podcastReady(f, flow)
        let other = try ReaderDeletionHTTPTransport.Configuration(projectID: f.configuration.projectID, appID: f.configuration.appID,
            endpointURL: XCTUnwrap(URL(string: "https://changed.example.invalid/reader")))
        XCTAssertFalse(f.auth.confirmAccountRecoveryLocalPodcast(flow, confirmation: confirmation, configuration: other, userConfirmed: true))
        XCTAssertEqual(f.podcastDisk.writes, 0)
        XCTAssertTrue(podcastConfirm(f, flow, confirmation)); await eventually { flow.coordinator.localPodcastStatus == .removed }
    }

    private func podcastsRemoved(_ f: Fixture) async throws -> Flow {
        let flow = try await resumesRemoved(f), c = try await podcastReady(f, flow)
        XCTAssertTrue(podcastConfirm(f, flow, c)); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.localPodcastStatus, .removed); return flow
    }
    private func introductionFixture() async throws -> (Fixture, Flow) {
        let f = try await fixture(); try f.seedFavorites(); try await seedResume(f); try seedPodcast(f); try f.introductionDisk.seed()
        return (f, try await podcastsRemoved(f))
    }
    private func introductionReady(_ f: Fixture, _ flow: Flow) async throws -> Model.LocalIntroductionConfirmation {
        XCTAssertTrue(f.auth.prepareAccountRecoveryLocalIntroduction(flow, configuration: f.configuration))
        await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.localIntroductionStatus, .ready)
        return try XCTUnwrap(flow.coordinator.localIntroductionConfirmation)
    }
    @discardableResult private func introductionConfirm(_ f: Fixture, _ flow: Flow, _ c: Model.LocalIntroductionConfirmation, consent: Bool = true) -> Bool {
        f.auth.confirmAccountRecoveryLocalIntroduction(flow, confirmation: c, configuration: f.configuration, userConfirmed: consent)
    }
    private func assertIntroductionRemoved(_ f: Fixture, _ flow: Flow) throws {
        XCTAssertEqual(flow.coordinator.localIntroductionStatus, .removed)
        XCTAssertTrue(try XCTUnwrap(flow.coordinator.localIntroductionReceipt).isComplete)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(f.introductionDisk.source)) as? [String: Any])
        XCTAssertEqual(json["completed"] as? Bool, true); XCTAssertEqual(json["replaying"] as? Bool, false)
        XCTAssertEqual(json["step"] as? String, "welcome"); XCTAssertEqual(json["selectedTopicIDs"] as? [String], [])
        XCTAssertNil(json["draftOwner"] as? String); XCTAssertFalse(f.introductionModel.isPresented)
        XCTAssertFalse(flow.coordinator.accountDeletionComplete); assertClosed(f)
    }
    func testIntroductionCleanupRequiresSingleUseSeparateConsentAndPreservesCompletionAndGuest() async throws {
        let (f, flow) = try await introductionFixture(), guest = f.introductionDisk.guest
        let c = try await introductionReady(f, flow), writes = f.introductionDisk.writes
        XCTAssertFalse(introductionConfirm(f, flow, c, consent: false)); XCTAssertEqual(f.introductionDisk.writes, writes)
        XCTAssertTrue(introductionConfirm(f, flow, c)); XCTAssertFalse(introductionConfirm(f, flow, c))
        await eventually { !flow.coordinator.hasPhysicalFlight }; try assertIntroductionRemoved(f, flow)
        XCTAssertEqual(f.introductionDisk.guest, guest); XCTAssertEqual(f.requests.count, 2)
        let reads = f.introductionDisk.reads
        XCTAssertFalse(f.introductionModel.start()); XCTAssertFalse(f.introductionModel.replay()); XCTAssertFalse(f.introductionModel.retry())
        XCTAssertEqual(f.introductionDisk.reads, reads)
    }
    func testIntroductionCleanupNeedsCompletedPodcastAndExplicitModel() async throws {
        let present = try await fixture(); try present.seedFavorites(); try await seedResume(present); try seedPodcast(present); try present.introductionDisk.seed()
        let beforePodcast = try await resumesRemoved(present)
        XCTAssertFalse(present.auth.prepareAccountRecoveryLocalIntroduction(beforePodcast, configuration: present.configuration), "A present model still requires original completed podcast proof")
        XCTAssertNil(present.introductionDisk.metadata)
        let f = try await fixture(); try f.seedFavorites(); try await seedResume(f); try seedPodcast(f); try f.introductionDisk.seed()
        f.includeIntroductionModel = false
        let flow = try await resumesRemoved(f)
        XCTAssertFalse(f.auth.prepareAccountRecoveryLocalIntroduction(flow, configuration: f.configuration))
        let c = try await podcastReady(f, flow); XCTAssertTrue(podcastConfirm(f, flow, c)); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertFalse(f.auth.prepareAccountRecoveryLocalIntroduction(flow, configuration: f.configuration))
        XCTAssertNil(f.introductionDisk.metadata)
    }
    func testIntroductionPreparationIsInertUntilExplicitAction() async throws {
        let (f, flow) = try await introductionFixture()
        let reads = f.introductionDisk.reads, metadataReads = f.introductionDisk.metadataReads
        for _ in 0..<100 { XCTAssertTrue(flow.coordinator.canPrepareLocalIntroductionCleanup); _ = flow.coordinator.localIntroductionMessage }
        XCTAssertEqual(f.introductionDisk.reads, reads); XCTAssertEqual(f.introductionDisk.metadataReads, metadataReads)
    }
    func testIntroductionCancellationRejectsOldConfirmationAndFreshRetrySucceeds() async throws {
        let (f, flow) = try await introductionFixture(), original = f.introductionDisk.source
        let c = try await introductionReady(f, flow)
        f.auth.cancelAccountRecoveryLocalIntroduction(flow)
        XCTAssertFalse(introductionConfirm(f, flow, c)); XCTAssertEqual(f.introductionDisk.source, original)
        let fresh = try await introductionReady(f, flow); XCTAssertTrue(introductionConfirm(f, flow, fresh))
        await eventually { !flow.coordinator.hasPhysicalFlight }; try assertIntroductionRemoved(f, flow)
    }
    func testIntroductionAccountRoundTripWhilePreparingRejectsOriginalReadAndReceipt() async throws {
        let (f, flow) = try await introductionFixture(), original = f.introductionDisk.source
        f.introductionDisk.onRead = { f.introductionDisk.onRead = nil; f.observe("reader-B"); f.observe("reader-A") }
        XCTAssertTrue(f.auth.prepareAccountRecoveryLocalIntroduction(flow, configuration: f.configuration))
        await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertNil(flow.coordinator.localIntroductionConfirmation); XCTAssertEqual(f.introductionDisk.source, original)
        XCTAssertNil(f.introductionDisk.metadata); assertClosed(f)
    }
    func testIntroductionChangedForeignSourceAfterConfirmationIsNotRewritten() async throws {
        let (f, flow) = try await introductionFixture(), c = try await introductionReady(f, flow)
        try f.introductionDisk.seed("reader-B"); let foreign = f.introductionDisk.source
        XCTAssertTrue(introductionConfirm(f, flow, c)); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.localIntroductionStatus, .failed); XCTAssertEqual(f.introductionDisk.source, foreign)
        let fresh = try await introductionReady(f, flow); XCTAssertTrue(introductionConfirm(f, flow, fresh))
        await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.localIntroductionStatus, .removed); XCTAssertEqual(f.introductionDisk.source, foreign)
        XCTAssertFalse(flow.coordinator.accountDeletionComplete)
    }
    func testIntroductionPendingWriteTimeoutRetainsPhysicalOwnershipAndNeedsFreshRetry() async throws {
        let (f, flow) = try await introductionFixture(), original = f.introductionDisk.source
        let c = try await introductionReady(f, flow)
        f.introductionDisk.onMetadataWrite = {
            f.introductionDisk.onMetadataWrite = nil
            XCTAssertTrue(flow.coordinator.hasPhysicalFlight); XCTAssertFalse(f.introductionModel.isPhysicallyIdle)
            f.timeouts.last?()
        }
        XCTAssertTrue(introductionConfirm(f, flow, c)); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.localIntroductionStatus, .failed); XCTAssertEqual(f.introductionDisk.source, original)
        XCTAssertNil(flow.coordinator.localIntroductionReceipt)
        let fresh = try await introductionReady(f, flow); XCTAssertTrue(introductionConfirm(f, flow, fresh))
        await eventually { !flow.coordinator.hasPhysicalFlight }; try assertIntroductionRemoved(f, flow)
    }
    func testIntroductionSourceWriteAccountRoundTripCannotPublishOldCompletion() async throws {
        let (f, flow) = try await introductionFixture(), c = try await introductionReady(f, flow)
        f.introductionDisk.onWrite = {
            f.introductionDisk.onWrite = nil; f.observe("reader-B"); f.observe("reader-A")
            XCTAssertFalse(f.introductionModel.isPhysicallyIdle); XCTAssertTrue(flow.coordinator.hasPhysicalFlight)
        }
        XCTAssertTrue(introductionConfirm(f, flow, c)); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertNil(flow.coordinator.localIntroductionReceipt); XCTAssertNotEqual(flow.coordinator.localIntroductionStatus, .removed)
        XCTAssertFalse(f.auth.prepareAccountRecoveryLocalIntroduction(flow, configuration: f.configuration)); assertClosed(f)
    }
    func testIntroductionFailedReadbackRetriesAlreadyClearedSourceWithoutAnotherSourceWrite() async throws {
        let (f, flow) = try await introductionFixture(), c = try await introductionReady(f, flow)
        f.introductionDisk.onWrite = { f.introductionDisk.onWrite = nil; f.introductionDisk.failSourceRead = true }
        XCTAssertTrue(introductionConfirm(f, flow, c)); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.localIntroductionStatus, .failed); XCTAssertNil(flow.coordinator.localIntroductionReceipt)
        let writes = f.introductionDisk.writes, fresh = try await introductionReady(f, flow)
        XCTAssertTrue(introductionConfirm(f, flow, fresh)); await eventually { !flow.coordinator.hasPhysicalFlight }
        try assertIntroductionRemoved(f, flow); XCTAssertEqual(f.introductionDisk.writes, writes)
    }
    func testIntroductionSourceWriteFailurePreservesDraftAndRetryCompletes() async throws {
        let (f, flow) = try await introductionFixture(), original = f.introductionDisk.source
        let c = try await introductionReady(f, flow); f.introductionDisk.failSourceWrite = true
        XCTAssertTrue(introductionConfirm(f, flow, c)); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.localIntroductionStatus, .failed); XCTAssertEqual(f.introductionDisk.source, original)
        let fresh = try await introductionReady(f, flow); XCTAssertTrue(introductionConfirm(f, flow, fresh))
        await eventually { !flow.coordinator.hasPhysicalFlight }; try assertIntroductionRemoved(f, flow)
    }

    private func historyFixture(capability: Bool = true, model: Bool = true, completeIntroduction: Bool = true) async throws -> (Fixture, Flow) {
        let f = try await fixture(); f.historyCapability = capability; f.includeHistoryModel = model
        try f.seedFavorites(); try await seedResume(f); try seedPodcast(f); try f.introductionDisk.seed(); try f.historyDisk.seed()
        let flow = try await podcastsRemoved(f)
        if completeIntroduction {
            let c = try await introductionReady(f, flow); XCTAssertTrue(introductionConfirm(f, flow, c))
            await eventually { !flow.coordinator.hasPhysicalFlight }; try assertIntroductionRemoved(f, flow)
        }
        return (f, flow)
    }
    private func historyReady(_ f: Fixture, _ flow: Flow) async throws -> Model.LocalHistoryConfirmation {
        XCTAssertTrue(f.auth.prepareAccountRecoveryLocalHistory(flow, configuration: f.configuration))
        await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.localHistoryStatus, .ready)
        return try XCTUnwrap(flow.coordinator.localHistoryConfirmation)
    }
    @discardableResult private func historyConfirm(_ f: Fixture, _ flow: Flow, _ c: Model.LocalHistoryConfirmation, consent: Bool = true) -> Bool {
        f.auth.confirmAccountRecoveryLocalHistory(flow, confirmation: c, configuration: f.configuration, userConfirmed: consent)
    }
    private func assertHistoryLocal(_ f: Fixture, _ flow: Flow, original: [String: Data]) throws {
        XCTAssertEqual(flow.coordinator.localHistoryStatus, .removed)
        let receipt = try XCTUnwrap(flow.coordinator.localHistoryReceipt)
        XCTAssertTrue(receipt.isLocalReadbackConfirmed); XCTAssertFalse(receipt.cloudCleanupComplete)
        let a = try XCTUnwrap(ReadingHistoryContext.confirmed(userID: "reader-A").namespace)
        XCTAssertEqual(try ReadingHistoryRecordCodec.decode(XCTUnwrap(f.historyDisk.records[a.storageKey]), namespace: a).entries, [])
        for (key,value) in original where key != a.storageKey { XCTAssertEqual(f.historyDisk.records[key], value) }
        XCTAssertEqual(Set(original.keys), Set(f.historyDisk.records.keys))
        XCTAssertEqual(f.historyDisk.normalEffects, 0); XCTAssertFalse(flow.coordinator.accountDeletionComplete)
        XCTAssertTrue(flow.coordinator.localHistoryMessage?.contains("iCloud") == true); assertClosed(f)
    }
    func testHistorySeparateSingleUseConsentOnlyConfirmsLocalReadbackAndPreservesOtherOwners() async throws {
        let (f,flow) = try await historyFixture(), original = f.historyDisk.records
        let c = try await historyReady(f,flow)
        XCTAssertFalse(historyConfirm(f,flow,c,consent:false)); XCTAssertEqual(f.historyDisk.writes,0)
        XCTAssertTrue(historyConfirm(f,flow,c)); XCTAssertFalse(historyConfirm(f,flow,c))
        await eventually { !flow.coordinator.hasPhysicalFlight }; try assertHistoryLocal(f,flow,original:original)
        XCTAssertEqual(f.historyDisk.writes,1); XCTAssertEqual(f.requests.count,2)
    }
    func testHistoryRequiresIntroductionReceiptAndExplicitModelAndCapability() async throws {
        let (early,flow) = try await historyFixture(completeIntroduction:false)
        XCTAssertFalse(early.auth.prepareAccountRecoveryLocalHistory(flow,configuration:early.configuration))
        for variant in 0..<2 {
            let (f,closed) = try await historyFixture(capability:variant != 0,model:variant != 1)
            XCTAssertFalse(closed.coordinator.canPrepareLocalHistoryCleanup)
            XCTAssertFalse(f.auth.prepareAccountRecoveryLocalHistory(closed,configuration:f.configuration))
            XCTAssertNil(closed.coordinator.localHistoryReceipt)
            XCTAssertEqual(f.historyDisk.reads,0); XCTAssertEqual(f.historyDisk.writes,0); XCTAssertEqual(f.historyDisk.normalEffects,0)
        }
    }
    func testHistoryRenderingAndSameModelLookupAreInert() async throws {
        let (f,flow) = try await historyFixture()
        for _ in 0..<100 {
            XCTAssertTrue(flow.coordinator.canPrepareLocalHistoryCleanup); _ = flow.coordinator.localHistoryMessage
            XCTAssertTrue(f.historyRuntime.localCleanupModel() === f.historyRuntime.model)
        }
        XCTAssertEqual(f.historyDisk.reads,0); XCTAssertEqual(f.historyDisk.writes,0); XCTAssertEqual(f.historyDisk.normalEffects,0)
    }
    func testHistoryCancelRetiresConfirmationAndRequiresFreshConsent() async throws {
        let (f,flow) = try await historyFixture(), original=f.historyDisk.records, c=try await historyReady(f,flow)
        f.auth.cancelAccountRecoveryLocalHistory(flow); XCTAssertFalse(historyConfirm(f,flow,c))
        let fresh=try await historyReady(f,flow); XCTAssertNotEqual(c,fresh)
        XCTAssertTrue(historyConfirm(f,flow,fresh)); await eventually { !flow.coordinator.hasPhysicalFlight }
        try assertHistoryLocal(f,flow,original:original)
    }
    func testHistoryChangedBytesAfterPrepareAreNotCleared() async throws {
        let (f,flow)=try await historyFixture(), c=try await historyReady(f,flow)
        let a=try XCTUnwrap(ReadingHistoryContext.confirmed(userID:"reader-A").namespace)
        let changed=try ReadingHistoryRecordCodec.encode(.init(entries:[.init(articleID:"cloud-replacement",read:true,progress:0.8)]),namespace:a)
        f.historyDisk.records[a.storageKey]=changed
        XCTAssertTrue(historyConfirm(f,flow,c)); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.localHistoryStatus,.failed); XCTAssertEqual(f.historyDisk.records[a.storageKey],changed)
        XCTAssertEqual(f.historyDisk.writes,0); XCTAssertNil(flow.coordinator.localHistoryReceipt)
    }
    func testHistoryOriginalPrepareCannotSurviveAccountRoundtrip() async throws {
        let (f,flow)=try await historyFixture(), original=f.historyDisk.records
        f.historyDisk.onRead={ [unowned f] in f.historyDisk.onRead=nil; f.observe("reader-B"); f.observe("reader-A") }
        XCTAssertTrue(f.auth.prepareAccountRecoveryLocalHistory(flow,configuration:f.configuration))
        await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertNil(flow.coordinator.localHistoryConfirmation); XCTAssertEqual(f.historyDisk.records,original)
        XCTAssertEqual(f.historyDisk.writes,0); assertClosed(f)
    }
    func testHistoryTimeoutDuringPendingRetainsPhysicalOwnershipAndAllowsFreshRetry() async throws {
        let (f,flow)=try await historyFixture(), original=f.historyDisk.records, c=try await historyReady(f,flow)
        var held=false
        f.historyDisk.onMetadataWrite={ [unowned f] in
            f.historyDisk.onMetadataWrite=nil
            held=flow.coordinator.hasPhysicalFlight && !f.historyRuntime.model.isPhysicallyIdle
            f.timeouts.last?()
            XCTAssertFalse(f.auth.prepareAccountRecoveryLocalHistory(flow,configuration:f.configuration))
        }
        XCTAssertTrue(historyConfirm(f,flow,c)); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertTrue(held); XCTAssertEqual(flow.coordinator.localHistoryStatus,.failed)
        XCTAssertEqual(f.historyDisk.records,original); XCTAssertNil(flow.coordinator.localHistoryReceipt)
        let fresh=try await historyReady(f,flow); XCTAssertTrue(historyConfirm(f,flow,fresh))
        await eventually { !flow.coordinator.hasPhysicalFlight }; try assertHistoryLocal(f,flow,original:original)
    }
    func testHistorySourceWriteRoundtripCannotPublishReceiptToNewGeneration() async throws {
        let (f,flow)=try await historyFixture(), c=try await historyReady(f,flow)
        f.historyDisk.onWrite={ [unowned f] in f.historyDisk.onWrite=nil; f.observe("reader-B"); f.observe("reader-A") }
        XCTAssertTrue(historyConfirm(f,flow,c)); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertNil(flow.coordinator.localHistoryReceipt); XCTAssertNotEqual(flow.coordinator.localHistoryStatus,.removed)
        XCTAssertFalse(f.auth.prepareAccountRecoveryLocalHistory(flow,configuration:f.configuration)); assertClosed(f)
    }
    func testHistoryReadbackFailureRetriesWithoutSecondSourceWriteOrCloudClaim() async throws {
        let (f,flow)=try await historyFixture(), original=f.historyDisk.records, c=try await historyReady(f,flow)
        f.historyDisk.failReadback=true; XCTAssertTrue(historyConfirm(f,flow,c)); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.localHistoryStatus,.failed); XCTAssertNil(flow.coordinator.localHistoryReceipt)
        let writes=f.historyDisk.writes, fresh=try await historyReady(f,flow)
        XCTAssertTrue(historyConfirm(f,flow,fresh)); await eventually { !flow.coordinator.hasPhysicalFlight }
        try assertHistoryLocal(f,flow,original:original); XCTAssertEqual(f.historyDisk.writes,writes)
    }
    func testHistorySourceWriteFailureKeepsOriginalUntilFreshConfirmation() async throws {
        let (f,flow)=try await historyFixture(), original=f.historyDisk.records, c=try await historyReady(f,flow)
        f.historyDisk.failWrite=true; XCTAssertTrue(historyConfirm(f,flow,c)); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.localHistoryStatus,.failed); XCTAssertEqual(f.historyDisk.records,original)
        let fresh=try await historyReady(f,flow); XCTAssertTrue(historyConfirm(f,flow,fresh))
        await eventually { !flow.coordinator.hasPhysicalFlight }; try assertHistoryLocal(f,flow,original:original)
    }

    private func pushFlow(_ f: Fixture) async throws -> Flow {
        f.includePushVault = true
        let flow = try XCTUnwrap(f.prepare(ticket(f)))
        XCTAssertTrue(f.confirm(flow)); _ = try await password(f, flow)
        await eventually { flow.coordinator.status == .scopedCloudDataRemoved && !flow.coordinator.hasPhysicalFlight }
        f.now += 1_000
        XCTAssertTrue(f.auth.confirmAccountRecoveryLedger(flow, configuration: f.configuration, userConfirmed: true))
        _ = try await password(f, flow)
        await eventually { flow.coordinator.status == .ledgerDataRemoved && !flow.coordinator.hasPhysicalFlight }
        return flow
    }
    private func preparePush(_ f: Fixture, _ flow: Flow) async throws -> Model.PushConfirmation {
        f.now += 1_000
        XCTAssertTrue(f.auth.prepareAccountRecoveryPush(flow, configuration: f.configuration))
        _ = try await password(f, flow)
        await eventually { flow.coordinator.pushStatus == .ready && !flow.coordinator.hasPhysicalFlight }
        return try XCTUnwrap(flow.coordinator.pushConfirmation)
    }
    private func finishPush(_ f: Fixture, _ flow: Flow, _ confirmation: Model.PushConfirmation) async throws {
        f.now += 1_000
        XCTAssertTrue(f.auth.confirmAccountRecoveryPush(flow, confirmation: confirmation, configuration: f.configuration, userConfirmed: true))
        _ = try await password(f, flow)
        await eventually { !flow.coordinator.hasPhysicalFlight }
    }
    private func reconstructedPushFixture(_ original: Fixture) async throws -> Fixture {
        let restored = try Fixture(restoring: original.root)
        restored.now = original.now + 5_000
        restored.pushDisk.replace(original.pushDisk.peek())
        addTeardownBlock { @MainActor in await restored.close() }
        if let task = restored.launch() { await task.value }
        return restored
    }
    private func restorePush(_ f: Fixture, _ flow: Flow) async {
        XCTAssertTrue(f.auth.prepareAccountRecoveryPush(flow, configuration: f.configuration))
        await eventually { !flow.coordinator.hasPhysicalFlight }
    }
    func testPushRestartRetainsExactOriginalCommitAndRequiresSeparateFreshProof() async throws {
        let f = try await fixture(); try f.seedPush()
        let flow = try await pushFlow(f), confirmation = try await preparePush(f, flow)
        f.httpFailure = true; try await finishPush(f, flow, confirmation)
        let original = try XCTUnwrap(f.requests.last?.httpBody)
        let retained = try XCTUnwrap(f.recovery.pushCommitCheckpoint)
        let restarted = try await reconstructedPushFixture(f)
        let recovered = try await pushFlow(restarted)
        XCTAssertTrue(recovered.coordinator.hasStoredPushCommit)
        XCTAssertEqual(restarted.pushDisk.reads, 0)
        await restorePush(restarted, recovered)
        XCTAssertEqual(recovered.coordinator.pushStatus, .awaitingRetry)
        XCTAssertTrue(recovered.coordinator.canRetryPushRetirement)
        XCTAssertFalse(recovered.coordinator.canPreparePushRetirement)
        XCTAssertNil(recovered.coordinator.pushConfirmation)
        XCTAssertEqual(restarted.requests.count, 2); XCTAssertEqual(restarted.sdkCalls, 2)
        XCTAssertFalse(restarted.auth.retryAccountRecoveryPush(recovered, configuration: restarted.configuration, userConfirmed: false))
        restarted.now += 1_000
        XCTAssertTrue(restarted.auth.retryAccountRecoveryPush(recovered, configuration: restarted.configuration, userConfirmed: true))
        _ = try await password(restarted, recovered)
        await eventually { !recovered.coordinator.hasPhysicalFlight }
        XCTAssertEqual(recovered.coordinator.pushStatus, .retired)
        XCTAssertEqual(restarted.requests.last?.httpBody, original)
        XCTAssertEqual(restarted.requests.count, 3); XCTAssertEqual(restarted.sdkCalls, 3)
        XCTAssertEqual(restarted.recovery.pushCommitCheckpoint, retained)
        XCTAssertEqual(restarted.pushDisk.writes, 0); assertClosed(restarted)
    }
    func testPushSuccessfulReceiptRemainsExactRetryAfterLogicalRestart() async throws {
        let f = try await fixture(); try f.seedPush(); let flow = try await pushFlow(f)
        let token = try await preparePush(f, flow)
        try await finishPush(f, flow, token)
        let original = f.requests.last?.httpBody
        let restarted = try await reconstructedPushFixture(f), restored = try await pushFlow(restarted)
        await restorePush(restarted, restored)
        XCTAssertEqual(restored.coordinator.pushStatus, .awaitingRetry)
        XCTAssertNil(restored.coordinator.pushReceipt)
        restarted.now += 1_000
        XCTAssertTrue(restored.coordinator.retryPushRetirement(userConfirmed: true))
        _ = try await password(restarted, restored)
        await eventually { !restored.coordinator.hasPhysicalFlight }
        XCTAssertEqual(restored.coordinator.pushStatus, .retired)
        XCTAssertEqual(restarted.requests.last?.httpBody, original)
        XCTAssertEqual(restarted.requests.count, 3); assertClosed(restarted)
    }
    func testPushReconstructedMissingChangedOrUnacknowledgedVaultCannotRegenerate() async throws {
        for mode in 0..<5 {
            let f = try await fixture(); try f.seedPush(); let flow = try await pushFlow(f)
            let confirmation = try await preparePush(f, flow)
            f.httpFailure = true; try await finishPush(f, flow, confirmation)
            let restarted = try await reconstructedPushFixture(f), restored = try await pushFlow(restarted)
            let saved = restarted.recovery.pushCommitCheckpoint
            if mode == 0 { restarted.pushDisk.replace(nil) }
            if mode == 1 { try restarted.seedPush(uid: "reader-B") }
            if mode == 2 { try restarted.seedPush(uid: nil) }
            if mode == 3 { try restarted.seedPush(ack: false) }
            if mode == 4 { try restarted.seedPush(status: .active) }
            await restorePush(restarted, restored)
            XCTAssertEqual(restored.coordinator.pushStatus, .unavailable)
            XCTAssertFalse(restored.coordinator.canRetryPushRetirement)
            XCTAssertEqual(restarted.requests.count, 2); XCTAssertEqual(restarted.sdkCalls, 2)
            XCTAssertEqual(restarted.recovery.pushCommitCheckpoint, saved)
            XCTAssertEqual(restarted.pushDisk.writes, 0); assertClosed(restarted)
        }
    }
    func testPushCommitReadbackFailureCanRepairOnlySameSavedRequestBeforeProvider() async throws {
        let f = try await fixture(); try f.seedPush(); let flow = try await pushFlow(f)
        let token = try await preparePush(f, flow)
        f.reads.failNext()
        XCTAssertTrue(flow.coordinator.confirmPushRetirement(token))
        await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.pushStatus, .unavailable)
        XCTAssertTrue(flow.coordinator.canRetryPushRetirement)
        XCTAssertEqual(f.requests.count, 3); XCTAssertEqual(f.sdkCalls, 3)
        let url = f.root.appendingPathComponent("reader-push-commit-v1.json")
        let bytes = try Data(contentsOf: url)
        f.now += 1_000
        XCTAssertTrue(flow.coordinator.retryPushRetirement(userConfirmed: true))
        _ = try await password(f, flow)
        await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.pushStatus, .retired)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(f.requests.count, 4); assertClosed(f)
    }
    func testPushPendingWriteRemainsPhysicalThroughCancelTimeoutAndAccountABA() async throws {
        for mode in 0..<3 {
            let f = try await fixture(); try f.seedPush(); let flow = try await pushFlow(f)
            let token = try await preparePush(f, flow), before = f.reads.count
            f.reads.holdNext(); XCTAssertTrue(flow.coordinator.confirmPushRetirement(token))
            await eventually { f.reads.count > before }
            if mode == 0 { flow.coordinator.cancelPushRetirement() }
            if mode == 1 { try XCTUnwrap(f.timeouts.last)() }
            if mode == 2 { f.observe("reader-B"); f.observe("reader-A") }
            XCTAssertTrue(flow.coordinator.hasPhysicalFlight)
            XCTAssertFalse(flow.coordinator.canRetryPushRetirement)
            f.reads.release(); await eventually { !flow.coordinator.hasPhysicalFlight }
            XCTAssertNotNil(f.recovery.pushCommitCheckpoint)
            XCTAssertEqual(f.requests.count, 3); XCTAssertEqual(f.sdkCalls, 3)
            XCTAssertNil(flow.coordinator.pushReceipt)
            XCTAssertEqual(flow.coordinator.canRetryPushRetirement, mode != 2); assertClosed(f)
        }
    }
    func testPushReconstructedRestoreCancellationCannotStartProviderOrPublishRetry() async throws {
        let f = try await fixture(); try f.seedPush(); let flow = try await pushFlow(f)
        let token = try await preparePush(f, flow); f.httpFailure = true; try await finishPush(f, flow, token)
        let restarted = try await reconstructedPushFixture(f), restored = try await pushFlow(restarted)
        let before = restarted.reads.count
        restarted.reads.holdNext(); XCTAssertTrue(restored.coordinator.preparePushRetirement())
        await eventually { restarted.reads.count > before }
        restored.coordinator.cancelPushRetirement()
        XCTAssertTrue(restored.coordinator.hasPhysicalFlight)
        restarted.reads.release(); await eventually { !restored.coordinator.hasPhysicalFlight }
        XCTAssertEqual(restored.coordinator.pushStatus, .cancelled)
        XCTAssertFalse(restored.coordinator.canRetryPushRetirement)
        XCTAssertEqual(restarted.requests.count, 2); XCTAssertEqual(restarted.sdkCalls, 2); assertClosed(restarted)
    }
    func testPushReconstructedRestoreAccountABARejectsOriginalFlow() async throws {
        let f = try await fixture(); try f.seedPush(); let flow = try await pushFlow(f)
        let token = try await preparePush(f, flow); f.httpFailure = true; try await finishPush(f, flow, token)
        let restarted = try await reconstructedPushFixture(f), restored = try await pushFlow(restarted)
        let before = restarted.reads.count
        restarted.reads.holdNext(); XCTAssertTrue(restored.coordinator.preparePushRetirement())
        await eventually { restarted.reads.count > before }
        restarted.observe("reader-B"); restarted.observe("reader-A")
        restarted.reads.release(); await eventually { !restored.coordinator.hasPhysicalFlight }
        XCTAssertFalse(restored.coordinator.canRetryPushRetirement)
        XCTAssertEqual(restarted.requests.count, 2); XCTAssertEqual(restarted.sdkCalls, 2); assertClosed(restarted)
    }
    func testPushPendingSidecarRemovalDuringCredentialsRejectsBeforeHTTP() async throws {
        let f = try await fixture(); try f.seedPush(); let flow = try await pushFlow(f)
        let token = try await preparePush(f, flow)
        f.credentialHook = {
            try? FileManager.default.removeItem(at: f.root.appendingPathComponent("reader-push-commit-v1.json"))
        }
        try await finishPush(f, flow, token)
        XCTAssertEqual(f.requests.count, 3)
        XCTAssertEqual(flow.coordinator.pushStatus, .unavailable)
        XCTAssertNil(flow.coordinator.pushReceipt); XCTAssertEqual(f.recovery.status, .unavailable)
        XCTAssertFalse(flow.coordinator.canPreparePushRetirement); assertClosed(f)
    }
    func testPushPendingSidecarChangeAfterHTTPRejectsReceiptWithoutReplacement() async throws {
        let f = try await fixture(); try f.seedPush(); let flow = try await pushFlow(f)
        let token = try await preparePush(f, flow)
        f.httpHook = {
            let url = f.root.appendingPathComponent("reader-push-commit-v1.json")
            guard let data = try? Data(contentsOf: url) else { return XCTFail("Missing retained commit before HTTP") }
            var changed = data; changed.append(0x20)
            do { try changed.write(to: url, options: .atomic) } catch { XCTFail("Could not inject changed sidecar") }
        }
        try await finishPush(f, flow, token)
        XCTAssertEqual(f.requests.count, 4)
        XCTAssertEqual(flow.coordinator.pushStatus, .unavailable)
        XCTAssertNil(flow.coordinator.pushReceipt); XCTAssertEqual(f.recovery.status, .unavailable)
        XCTAssertFalse(flow.coordinator.canPreparePushRetirement); assertClosed(f)
    }
    func testPushStoredSidecarContainsNoInstallationKeyTokenOrCredentials() async throws {
        let f = try await fixture(); try f.seedPush(); let flow = try await pushFlow(f)
        let token = try await preparePush(f, flow)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("reader-push-commit-v1.json").path))
        try await finishPush(f, flow, token)
        let bytes = try Data(contentsOf: f.root.appendingPathComponent("reader-push-commit-v1.json"))
        let raw = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(raw.contains(String(repeating: "k", count: 48)))
        for key in ["token", "nonce", "credentials", "installationKey", "Authorization"] {
            XCTAssertFalse(raw.contains("\"" + key + "\""))
        }
        XCTAssertTrue(raw.contains(try XCTUnwrap(f.recovery.pushCommitCheckpoint).snapshot.requestId))
        XCTAssertLessThan(bytes.count, 16_384); assertClosed(f)
    }

    func testPushParentAndLedgerDoNotReadVaultOrInventInstallationEvidence() async throws {
        let f = try await fixture(); try f.seedPush(); let bytes = f.pushDisk.peek()
        let flow = try await pushFlow(f)
        XCTAssertEqual(f.pushDisk.reads, 0); XCTAssertEqual(f.pushDisk.writes, 0)
        XCTAssertEqual(f.pushDisk.peek(), bytes); XCTAssertNil(flow.coordinator.pushConfirmation)
        XCTAssertEqual(f.requests.count, 2); XCTAssertFalse(flow.coordinator.accountDeletionComplete); assertClosed(f)
    }
    func testPushPendingAndActiveACKKeepSeparateEpochsAndFreshProofForEveryPhase() async throws {
        for status in [PushRegistrationReceipt.Status.pending, .active] {
            let f = try await fixture(); try f.seedPush(status: status); let bytes = f.pushDisk.peek()
            let flow = try await pushFlow(f), token = try await preparePush(f, flow)
            XCTAssertNil(flow.coordinator.pushReceipt); XCTAssertEqual(f.requests.count, 3)
            XCTAssertFalse(f.auth.confirmAccountRecoveryPush(flow, confirmation: token, configuration: f.configuration, userConfirmed: false))
            try await finishPush(f, flow, token)
            XCTAssertEqual(flow.coordinator.pushStatus, .retired); XCTAssertEqual(f.sdkCalls, 4)
            XCTAssertEqual(Set(f.requests.compactMap { $0.value(forHTTPHeaderField: "Authorization") }).count, 4)
            let request = try JSONDecoder().decode(Contract.PushRequest.self, from: XCTUnwrap(f.requests.last?.httpBody))
            XCTAssertEqual(request.membershipEpoch, 7); XCTAssertEqual(request.installation.expected.ownerEpoch, 29)
            XCTAssertEqual(request.installation.expected.revision, 42); XCTAssertEqual(request.installation.expected.clientRevision, 3)
            XCTAssertEqual(f.pushDisk.peek(), bytes); XCTAssertEqual(f.pushDisk.writes, 0)
            XCTAssertEqual(flow.coordinator.status, .ledgerDataRemoved); XCTAssertNotNil(flow.coordinator.ledgerReceipt)
            XCTAssertTrue(flow.coordinator.canPrepareLocalFavoritesCleanup)
            XCTAssertFalse(flow.coordinator.accountDeletionComplete); assertClosed(f)
        }
    }
    func testPushMissingRecordACKOtherOwnerGuestAndInvalidReadStayUnavailableWithoutProvider() async throws {
        for mode in 0..<5 {
            let f = try await fixture()
            if mode == 1 { try f.seedPush(ack: false) }
            if mode == 2 { try f.seedPush(uid: "reader-B") }
            if mode == 3 { try f.seedPush(uid: nil) }
            if mode == 4 { f.pushDisk.failRead = true }
            let flow = try await pushFlow(f)
            XCTAssertTrue(f.auth.prepareAccountRecoveryPush(flow, configuration: f.configuration))
            await eventually { !flow.coordinator.hasPhysicalFlight }
            XCTAssertEqual(flow.coordinator.pushStatus, .unavailable); XCTAssertNil(flow.coordinator.pushConfirmation)
            XCTAssertEqual(f.requests.count, 2); XCTAssertEqual(f.sdkCalls, 2); XCTAssertEqual(f.pushDisk.writes, 0)
            XCTAssertTrue(flow.coordinator.canPreparePushRetirement); assertClosed(f)
        }
    }
    func testPushChangedRecordBeforeCommitRejectsWithoutNewProvider() async throws {
        let f = try await fixture(); try f.seedPush(); let flow = try await pushFlow(f)
        let token = try await preparePush(f, flow); try f.seedPush(uid: "reader-B")
        XCTAssertTrue(f.auth.confirmAccountRecoveryPush(flow, confirmation: token, configuration: f.configuration, userConfirmed: true))
        await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(f.sdkCalls, 3); XCTAssertEqual(f.requests.count, 3)
        XCTAssertEqual(flow.coordinator.pushStatus, .unavailable); XCTAssertFalse(flow.coordinator.canPreparePushRetirement)
        XCTAssertFalse(flow.coordinator.confirmPushRetirement(token)); assertClosed(f)
    }
    func testPushChangedRecordDuringCredentialsRejectsBeforeHTTP() async throws {
        let f = try await fixture(); try f.seedPush(); let flow = try await pushFlow(f)
        let token = try await preparePush(f, flow)
        f.credentialHook = { try? f.seedPush(uid: "reader-B") }
        try await finishPush(f, flow, token)
        XCTAssertEqual(f.requests.count, 3); XCTAssertEqual(flow.coordinator.pushStatus, .unavailable)
        XCTAssertNil(flow.coordinator.pushReceipt); assertClosed(f)
    }
    func testPushOldHTTPResultAfterBindingReplacementNeverBecomesConfirmation() async throws {
        let f = try await fixture(); try f.seedPush(); let flow = try await pushFlow(f)
        f.httpHook = { try? f.seedPush(uid: "reader-B") }
        XCTAssertTrue(f.auth.prepareAccountRecoveryPush(flow, configuration: f.configuration)); _ = try await password(f, flow)
        await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.pushStatus, .unavailable); XCTAssertNil(flow.coordinator.pushConfirmation)
        XCTAssertEqual(f.requests.count, 3); assertClosed(f)
    }
    func testPushAccountRoundTripOrGuestRejectsLateHeldReauthentication() async throws {
        for uid in [Optional("reader-B"), nil, Optional("reader-A")] {
            let f = try await fixture(); try f.seedPush(); let flow = try await pushFlow(f)
            let gate = f.holdSDK(); XCTAssertTrue(f.auth.prepareAccountRecoveryPush(flow, configuration: f.configuration))
            _ = try await password(f, flow); await eventually { gate.entered }
            f.observe("reader-B"); f.observe(uid)
            XCTAssertTrue(flow.coordinator.hasPhysicalFlight); gate.release()
            await eventually { !flow.coordinator.hasPhysicalFlight }
            XCTAssertEqual(f.requests.count, 2); XCTAssertNil(flow.coordinator.pushConfirmation)
            XCTAssertFalse(flow.coordinator.canPreparePushRetirement); assertClosed(f)
        }
    }
    func testPushTimeoutBeforeAdmissionHoldsPhysicalSlotAndRejectsLateProviderReturn() async throws {
        let f = try await fixture(); try f.seedPush(); let flow = try await pushFlow(f)
        let gate = f.holdSDK(); XCTAssertTrue(f.auth.prepareAccountRecoveryPush(flow, configuration: f.configuration))
        _ = try await password(f, flow); await eventually { gate.entered }
        try XCTUnwrap(f.timeouts.last)()
        XCTAssertEqual(flow.coordinator.pushStatus, .timedOut); XCTAssertTrue(flow.coordinator.hasPhysicalFlight)
        XCTAssertFalse(flow.coordinator.canPreparePushRetirement); gate.release()
        await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(f.requests.count, 2); XCTAssertNil(flow.coordinator.pushConfirmation)
        XCTAssertEqual(flow.coordinator.pushStatus, .timedOut); assertClosed(f)
    }
    func testPushLostCommitReplyRetriesSameSnapshotWithFreshProofAndNoPrepare() async throws {
        let f = try await fixture(); try f.seedPush(); let flow = try await pushFlow(f), token = try await preparePush(f, flow)
        f.httpFailure = true; try await finishPush(f, flow, token)
        let first = try XCTUnwrap(f.requests.last); XCTAssertEqual(flow.coordinator.pushStatus, .unavailable)
        XCTAssertTrue(flow.coordinator.canRetryPushRetirement); XCTAssertFalse(flow.coordinator.canPreparePushRetirement)
        XCTAssertFalse(flow.coordinator.retryPushRetirement(userConfirmed: false))
        f.now += 1_000
        XCTAssertTrue(f.auth.retryAccountRecoveryPush(flow, configuration: f.configuration, userConfirmed: true))
        _ = try await password(f, flow); await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.pushStatus, .retired)
        XCTAssertEqual(first.httpBody, f.requests.last?.httpBody)
        XCTAssertNotEqual(first.value(forHTTPHeaderField: "Authorization"), f.requests.last?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(f.requests.count, 5); XCTAssertEqual(f.pushDisk.writes, 0); assertClosed(f)
    }
    func testPushTimeoutAndCancelAfterCommitStartKeepSnapshotUntilPhysicalReturn() async throws {
        for timeout in [false, true] {
            let f = try await fixture(); try f.seedPush(); let flow = try await pushFlow(f), token = try await preparePush(f, flow)
            let gate = Gate(); f.allGates.append(gate); f.httpGate = gate
            XCTAssertTrue(flow.coordinator.confirmPushRetirement(token)); _ = try await password(f, flow)
            await eventually { gate.entered }
            if timeout { try XCTUnwrap(f.timeouts.last)() } else { flow.coordinator.cancelPushRetirement() }
            XCTAssertTrue(flow.coordinator.hasPhysicalFlight); XCTAssertFalse(flow.coordinator.canRetryPushRetirement)
            gate.release(); await eventually { !flow.coordinator.hasPhysicalFlight }
            XCTAssertNil(flow.coordinator.pushReceipt); XCTAssertTrue(flow.coordinator.canRetryPushRetirement)
            let before = f.requests.last?.httpBody; f.now += 1_000
            XCTAssertTrue(flow.coordinator.retryPushRetirement(userConfirmed: true)); _ = try await password(f, flow)
            await eventually { !flow.coordinator.hasPhysicalFlight }
            XCTAssertEqual(flow.coordinator.pushStatus, .retired); XCTAssertEqual(f.requests.last?.httpBody, before); assertClosed(f)
        }
    }
    func testPushCancelledConfirmationCannotBeReusedOrStartAProvider() async throws {
        let f = try await fixture(); try f.seedPush(); let flow = try await pushFlow(f), token = try await preparePush(f, flow)
        f.auth.cancelAccountRecoveryPush(flow)
        XCTAssertFalse(flow.coordinator.confirmPushRetirement(token)); XCTAssertEqual(f.requests.count, 3)
        XCTAssertTrue(flow.coordinator.canPreparePushRetirement); XCTAssertFalse(flow.coordinator.canRetryPushRetirement)
        let next = try await preparePush(f, flow); XCTAssertNotEqual(token, next)
        XCTAssertFalse(flow.coordinator.confirmPushRetirement(token)); assertClosed(f)
    }
    func testPushPublicationReentryRevokesBeforeNewHTTP() async throws {
        let f = try await fixture(); try f.seedPush(); let flow = try await pushFlow(f)
        var fired = false
        let subscription = flow.coordinator.objectWillChange.sink {
            if !fired { fired = true; flow.coordinator.cancelPushRetirement() }
        }
        XCTAssertFalse(flow.coordinator.preparePushRetirement())
        await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(f.requests.count, 2); XCTAssertEqual(f.sdkCalls, 2)
        withExtendedLifetime(subscription) {}; assertClosed(f)
    }
    func testPushSchedulerReentryCannotLaunchCancelledTask() async throws {
        let f = try await fixture(); try f.seedPush(); let flow = try await pushFlow(f)
        f.deadlineHook = { flow.coordinator.cancelPushRetirement() }
        XCTAssertFalse(flow.coordinator.preparePushRetirement())
        await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(f.requests.count, 2); XCTAssertEqual(f.sdkCalls, 2); assertClosed(f)
    }
    func testPushFinalClockReentryCannotBorrowFreshAccountAuthority() async throws {
        let f = try await fixture(); try f.seedPush(); let flow = try await pushFlow(f)
        f.clockHook = { f.observe("reader-B"); f.observe("reader-A") }
        XCTAssertTrue(flow.coordinator.preparePushRetirement())
        await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(f.requests.count, 2); XCTAssertNil(flow.coordinator.pushConfirmation); assertClosed(f)
    }
    func testPushCheckpointFailureLeavesOriginalDataAndNoHTTP() async throws {
        let f = try await fixture(); try f.seedPush(); let flow = try await pushFlow(f)
        f.reads.failNext(); XCTAssertTrue(flow.coordinator.preparePushRetirement())
        await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.pushStatus, .unavailable); XCTAssertEqual(f.requests.count, 2)
        XCTAssertEqual(f.pushDisk.writes, 0); XCTAssertFalse(flow.coordinator.accountDeletionComplete); assertClosed(f)
    }

    func testPushCheckpointReadReentryCannotHideChangedVaultAfterFirstObservation() async throws {
        let f = try await fixture(); try f.seedPush(); let flow = try await pushFlow(f)
        let token = try await preparePush(f, flow)
        let disk = f.pushDisk
        f.reads.setHook { disk.replace(nil) }
        XCTAssertTrue(flow.coordinator.confirmPushRetirement(token))
        await eventually { !flow.coordinator.hasPhysicalFlight }
        f.reads.setHook(nil)
        XCTAssertEqual(f.requests.count, 3); XCTAssertEqual(f.sdkCalls, 3)
        XCTAssertEqual(flow.coordinator.pushStatus, .unavailable); assertClosed(f)
    }

    func testPushPhysicalFinishCancellationHookCannotClearReplacementPreparation() async throws {
        let f = try await fixture(); try f.seedPush(); let flow = try await pushFlow(f)
        f.deadlineCancelHook = {
            f.deadlineCancelHook = nil
            flow.coordinator.cancelPushRetirement()
            XCTAssertTrue(flow.coordinator.preparePushRetirement())
        }
        XCTAssertTrue(flow.coordinator.preparePushRetirement())
        let first = try await password(f, flow)
        await eventually { f.requests.count == 3 && flow.prompts.email.presentation?.action != first.action }
        XCTAssertNil(flow.coordinator.pushConfirmation)
        XCTAssertTrue(flow.coordinator.hasPhysicalFlight)
        let second = try await password(f, flow)
        XCTAssertNotEqual(first.action, second.action)
        await eventually { !flow.coordinator.hasPhysicalFlight }
        XCTAssertEqual(flow.coordinator.pushStatus, .ready); XCTAssertNotNil(flow.coordinator.pushConfirmation)
        XCTAssertEqual(f.requests.count, 4); XCTAssertEqual(f.pushDisk.writes, 0); assertClosed(f)
    }

}
