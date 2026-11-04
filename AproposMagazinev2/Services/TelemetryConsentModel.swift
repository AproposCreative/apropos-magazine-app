import Foundation

/// Device choices for Analytics and LOCAL diagnostics. This record never grants
/// permission to upload Crashlytics reports or to associate telemetry with an account.
/// All effects are synchronous and injected; construction starts no storage or SDK work.
final class TelemetryConsentModel: @unchecked Sendable {
    struct Choices: Equatable, Sendable {
        let analyticsEnabled: Bool
        let diagnosticsEnabled: Bool
        static let off = Choices(analyticsEnabled: false, diagnosticsEnabled: false)
    }

    enum Channel: Equatable, Sendable { case analytics, diagnostics }
    enum State: Equatable, Sendable {
        case unloaded, updating, notChosen, ready
        case invalidRecord, unsupportedVersion, readFailed, writeFailed, invalidClock
    }
    struct Snapshot: Equatable, Sendable {
        let choices: Choices
        let hasExplicitChoice: Bool
        let state: State
        let generation: UUID
    }
    struct Ticket: Equatable, Sendable {
        fileprivate let modelID: UUID
        fileprivate let generation: UUID
        fileprivate let channel: Channel
    }
    struct Storage: Sendable {
        let read: @Sendable () throws -> Data?
        let write: @Sendable (Data) throws -> Void
    }
    struct Sinks: Sendable {
        /// Clear buffers only. These closures must not start collection or upload.
        let clearAnalytics: @Sendable () -> Void
        let clearDiagnostics: @Sendable () -> Void
    }

    private struct Record: Codable {
        let schemaVersion: Int
        let policyVersion: Int
        let analyticsEnabled: Bool
        let localDiagnosticsEnabled: Bool
        let recordedAtMs: Int64
    }
    private static let recordKeys: Set<String> = [
        "schemaVersion", "policyVersion", "analyticsEnabled", "localDiagnosticsEnabled", "recordedAtMs"
    ]
    private static let maximumRecordBytes = 2048
    private static let maximumMilliseconds: Double = 9_007_199_254_740_991
    private let lock = NSRecursiveLock()
    private let storage: Storage
    private let now: @Sendable () -> Date
    private let sinks: Sinks
    private let modelID = UUID()
    private var generation = UUID()
    private var choices = Choices.off
    private var hasExplicitChoice = false
    private var state = State.unloaded
    private var loaded = false
    private var mutating = false
    private var contextWasSet = false
    private var context: String?

    init(storage: Storage, now: @escaping @Sendable () -> Date, sinks: Sinks) {
        self.storage = storage
        self.now = now
        self.sinks = sinks
    }

    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return snapshotLocked()
    }

    /// Read once. A failed withdrawal must never be undone by reloading an old grant.
    @discardableResult
    func load() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        guard !loaded else { return snapshotLocked() }
        guard !mutating else { return rejectReentrantMutation() }
        loaded = true
        mutating = true
        defer { mutating = false }
        let ticket = invalidateLocked()
        clearLocked()
        guard generation == ticket else { return snapshotLocked() }
        let data: Data?
        do { data = try storage.read() }
        catch {
            if generation == ticket { state = .readFailed }
            return snapshotLocked()
        }
        guard generation == ticket else { return snapshotLocked() }
        guard let data else { state = .notChosen; return snapshotLocked() }
        guard data.count <= Self.maximumRecordBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Self.recordKeys,
              let record = try? JSONDecoder().decode(Record.self, from: data) else {
            state = .invalidRecord
            return snapshotLocked()
        }
        guard record.schemaVersion == 1, record.policyVersion == 1 else {
            state = .unsupportedVersion
            return snapshotLocked()
        }
        let observedTime = milliseconds()
        guard generation == ticket else { return snapshotLocked() }
        guard let time = observedTime else { state = .invalidClock; return snapshotLocked() }
        guard record.recordedAtMs > 0, Double(record.recordedAtMs) <= Self.maximumMilliseconds,
              record.recordedAtMs <= time else {
            state = .invalidRecord
            return snapshotLocked()
        }
        choices = Choices(analyticsEnabled: record.analyticsEnabled, diagnosticsEnabled: record.localDiagnosticsEnabled)
        hasExplicitChoice = true
        state = .ready
        return snapshotLocked()
    }

    /// An explicit user choice. Failure leaves BOTH gates off; no old grant is restored.
    /// A store that refuses all writes cannot guarantee revocation survives process loss.
    @discardableResult
    func setChoices(_ desired: Choices) -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        guard !mutating else { return rejectReentrantMutation() }
        if loaded, state == .ready, hasExplicitChoice, choices == desired { return snapshotLocked() }
        loaded = true
        mutating = true
        defer { mutating = false }
        let ticket = invalidateLocked()
        clearLocked()
        guard generation == ticket else { return snapshotLocked() }
        let observedTime = milliseconds()
        guard generation == ticket else { return snapshotLocked() }
        guard let time = observedTime else { state = .invalidClock; return snapshotLocked() }
        let record = Record(schemaVersion: 1, policyVersion: 1, analyticsEnabled: desired.analyticsEnabled,
                            localDiagnosticsEnabled: desired.diagnosticsEnabled, recordedAtMs: time)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            try storage.write(encoder.encode(record))
        } catch {
            if generation == ticket { state = .writeFailed }
            return snapshotLocked()
        }
        guard generation == ticket else { return snapshotLocked() }
        let completedTime = milliseconds()
        guard generation == ticket else { return snapshotLocked() }
        guard let completedAt = completedTime, completedAt >= time else {
            state = .invalidClock
            return snapshotLocked()
        }
        choices = desired
        hasExplicitChoice = true
        state = .ready
        return snapshotLocked()
    }

    /// Account changes invalidate queued evidence and clear context buffers. The
    /// per-device choice is preserved; this method never creates or persists a grant.
    @discardableResult
    func changeContext(to identifier: String?) -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        guard !mutating else { return rejectReentrantMutation() }
        if contextWasSet, context == identifier { return snapshotLocked() }
        contextWasSet = true
        context = identifier
        mutating = true
        defer { mutating = false }
        let oldChoices = choices, oldExplicit = hasExplicitChoice, oldState = state
        let ticket = invalidateLocked()
        clearLocked()
        guard generation == ticket else { return snapshotLocked() }
        choices = oldChoices
        hasExplicitChoice = oldExplicit
        state = oldState
        return snapshotLocked()
    }

    /// Capture on the originating thread BEFORE dispatching a callback elsewhere.
    func captureTicket(for channel: Channel) -> Ticket? {
        lock.lock(); defer { lock.unlock() }
        guard permitsLocked(channel) else { return nil }
        return Ticket(modelID: modelID, generation: generation, channel: channel)
    }

    /// No async work is allowed inside `perform`. The check and synchronous start
    /// are serialized with withdrawal. An already-started SDK effect cannot be undone.
    @discardableResult
    func withPermission(_ ticket: Ticket, perform: () -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard ticket.modelID == modelID, ticket.generation == generation, permitsLocked(ticket.channel) else { return false }
        perform()
        return true
    }

    /// Prefer this form at a concrete sink so a ticket for the other purpose cannot be reused.
    @discardableResult
    func withPermission(_ ticket: Ticket, for channel: Channel, perform: () -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard ticket.channel == channel else { return false }
        return withPermission(ticket, perform: perform)
    }

    private func permitsLocked(_ channel: Channel) -> Bool {
        guard loaded, contextWasSet, !mutating, state == .ready, hasExplicitChoice else { return false }
        return channel == .analytics ? choices.analyticsEnabled : choices.diagnosticsEnabled
    }
    private func snapshotLocked() -> Snapshot {
        Snapshot(choices: choices, hasExplicitChoice: hasExplicitChoice, state: state, generation: generation)
    }
    private func invalidateLocked() -> UUID {
        generation = UUID()
        choices = .off
        hasExplicitChoice = false
        state = .updating
        return generation
    }
    private func clearLocked() {
        sinks.clearAnalytics()
        sinks.clearDiagnostics()
    }
    private func rejectReentrantMutation() -> Snapshot {
        generation = UUID()
        choices = .off
        hasExplicitChoice = false
        state = .writeFailed
        return snapshotLocked()
    }
    private func milliseconds() -> Int64? {
        let value = now().timeIntervalSince1970 * 1000
        guard value.isFinite, value >= 1, value <= Self.maximumMilliseconds else { return nil }
        return Int64(value.rounded(.down))
    }
}
