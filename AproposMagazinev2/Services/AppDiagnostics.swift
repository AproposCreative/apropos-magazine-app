import Foundation
import CoreFoundation

/// Optional local diagnostics. Before explicit composition there is no storage,
/// OSLog, Firebase or background work. Crashlytics transport is not part of this API.
enum AppDiagnostics {
    struct Storage: Sendable {
        let read: @Sendable () -> [String]
        let write: @Sendable ([String]) -> Void
        let clear: @Sendable () -> Void
    }
    private struct Configuration: Sendable {
        let id: UUID
        let model: TelemetryConsentModel
        let storage: Storage
        let emit: @Sendable (TelemetryDiagnosticPolicy.Event) -> Void
        let now: @Sendable () -> Date
    }
    private static let lock = NSRecursiveLock()
    private static var configuration: Configuration?
    private static let maxEntries = 80

    static func configure(model: TelemetryConsentModel, storage: Storage,
                          emit: @escaping @Sendable (TelemetryDiagnosticPolicy.Event) -> Void,
                          now: @escaping @Sendable () -> Date) {
        lock.lock(); defer { lock.unlock() }
        configuration = Configuration(id: UUID(), model: model, storage: storage, emit: emit, now: now)
    }

    /// Synchronous, including persistence. Storage callbacks must be bounded and
    /// must not acquire another model's lock or start asynchronous telemetry work.
    static func clearBuffers() {
        lock.lock(); defer { lock.unlock() }
        configuration?.storage.clear()
    }

    static func breadcrumb(_ message: String) {
        guard let event = TelemetryDiagnosticPolicy.breadcrumb(message), let config = current(),
              let ticket = config.model.captureTicket(for: .diagnostics) else { return }
        enqueue(event, ticket: ticket, config: config)
    }

    static func recordOperational(_ code: TelemetryDiagnosticPolicy.OperationalCode) {
        guard let config = current(), let ticket = config.model.captureTicket(for: .diagnostics) else { return }
        enqueue(TelemetryDiagnosticPolicy.operational(code), ticket: ticket, config: config)
    }

    static func recordError(_ error: Error, context: String? = nil) {
        // Deliberately never inspect or retain the Error's description, domain or userInfo.
        let event = TelemetryDiagnosticPolicy.error(context: context)
        guard let config = current(), let ticket = config.model.captureTicket(for: .diagnostics) else { return }
        enqueue(event, ticket: ticket, config: config)
    }

    static func recentBreadcrumbs() -> [String] {
        guard let config = current(), let ticket = config.model.captureTicket(for: .diagnostics) else { return [] }
        var result: [String] = []
        config.model.withPermission(ticket, for: .diagnostics) {
            lock.lock(); defer { lock.unlock() }
            guard configuration?.id == config.id else { return }
            let stored = config.storage.read()
            guard configuration?.id == config.id else { return }
            var projected: [String] = []
            config.model.withPermission(ticket, for: .diagnostics) {
                projected = stored.suffix(maxEntries).compactMap { validatedLine($0, now: config.now()) }
            }
            guard configuration?.id == config.id else { return }
            config.model.withPermission(ticket, for: .diagnostics) { result = projected }
        }
        return result
    }

    static func recordMetricCounts(_ counts: [String: Int], begin: Date, end: Date, since: Date,
                                   ticket: TelemetryConsentModel.Ticket, model: TelemetryConsentModel) {
        guard let event = TelemetryDiagnosticPolicy.metrics(counts), let config = current(), config.model === model else { return }
        Task { @MainActor in
            model.withPermission(ticket, for: .diagnostics) {
                guard TelemetryDiagnosticPolicy.permitsInterval(begin: begin, end: end, since: since, now: config.now()) else { return }
                append(event, ticket: ticket, config: config)
            }
        }
    }

    private static func current() -> Configuration? {
        lock.lock(); defer { lock.unlock() }
        return configuration
    }
    private static func enqueue(_ event: TelemetryDiagnosticPolicy.Event, ticket: TelemetryConsentModel.Ticket,
                                config: Configuration) {
        Task { @MainActor in
            config.model.withPermission(ticket, for: .diagnostics) { append(event, ticket: ticket, config: config) }
        }
    }
    private static func append(_ event: TelemetryDiagnosticPolicy.Event, ticket: TelemetryConsentModel.Ticket, config: Configuration) {
        lock.lock(); defer { lock.unlock() }
        guard configuration?.id == config.id, let line = encodedLine(event, now: config.now()) else { return }
        guard configuration?.id == config.id,
              config.model.withPermission(ticket, for: .diagnostics, perform: {}) else { return }
        var entries = config.storage.read().suffix(maxEntries - 1).compactMap { validatedLine($0, now: config.now()) }
        // A reentrant injected storage callback may reconfigure the composition.
        guard configuration?.id == config.id,
              config.model.withPermission(ticket, for: .diagnostics, perform: {}) else { return }
        entries.append(line)
        config.storage.write(entries)
        guard configuration?.id == config.id else { return }
        guard config.model.withPermission(ticket, for: .diagnostics, perform: {}) else {
            // A reentrant write callback may revoke and clear before its own write
            // finishes; remove that stale local completion without emitting it.
            config.storage.clear()
            return
        }
        config.model.withPermission(ticket, for: .diagnostics) { config.emit(event) }
    }
    private static func encodedLine(_ event: TelemetryDiagnosticPolicy.Event, now: Date) -> String? {
        let milliseconds = now.timeIntervalSince1970 * 1000
        guard milliseconds.isFinite, milliseconds >= 1, milliseconds <= 9_007_199_254_740_991,
              let data = try? JSONSerialization.data(withJSONObject: ["code": event.code, "measurements": event.measurements,
                "recordedAtMs": Int64(milliseconds.rounded(.down))], options: .sortedKeys), data.count <= 512 else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private static func validatedLine(_ raw: String, now: Date) -> String? {
        guard raw.utf8.count <= 512, let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["code", "measurements", "recordedAtMs"],
              let code = object["code"] as? String, let rawMeasurements = object["measurements"] as? [String: NSNumber],
              rawMeasurements.count <= 9,
              rawMeasurements.values.allSatisfy({ CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue.isFinite && $0.doubleValue >= 0 && $0.doubleValue <= 1_000_000 && $0.doubleValue.rounded(.down) == $0.doubleValue }),
              let timestamp = object["recordedAtMs"] as? NSNumber,
              CFGetTypeID(timestamp) != CFBooleanGetTypeID(), timestamp.doubleValue.isFinite,
              timestamp.doubleValue.rounded(.down) == timestamp.doubleValue,
              timestamp.doubleValue >= 1, timestamp.doubleValue <= now.timeIntervalSince1970 * 1000 else { return nil }
        let measurements = rawMeasurements.mapValues { $0.intValue }
        let event: TelemetryDiagnosticPolicy.Event?
        if let operation = TelemetryDiagnosticPolicy.OperationalCode(rawValue: code), measurements.isEmpty { event = TelemetryDiagnosticPolicy.operational(operation) }
        else if code == "metrickit_counts" { event = TelemetryDiagnosticPolicy.metrics(measurements) }
        else if code == "podcast_ttf_audio", measurements.isEmpty || (measurements.count == 1 && (0...300000).contains(measurements["milliseconds"] ?? -1)) {
            event = .init(code: code, measurements: measurements)
        } else if measurements.isEmpty {
            if code.hasPrefix("error.") {
                let candidate = TelemetryDiagnosticPolicy.error(context: String(code.dropFirst("error.".count)))
                event = candidate.code == code ? candidate : nil
            } else {
                let sample = code == "push_subscribed" ? "push_subscribed_" : code == "metrickit_exits" || code == "metrickit_diag" ? code + " " : code + ":"
                let candidate = TelemetryDiagnosticPolicy.breadcrumb(code) ?? TelemetryDiagnosticPolicy.breadcrumb(sample)
                event = candidate?.code == code ? candidate : nil
            }
        } else { event = nil }
        guard let event else { return nil }
        return encodedLine(event, now: Date(timeIntervalSince1970: timestamp.doubleValue / 1000))
    }
}
