import Foundation
import Combine

/// UI projection over an explicitly supplied device-consent model. Construction
/// reads only its current snapshot; SDK adapters and storage setup remain with the caller.
@MainActor
final class TelemetryConsentController: ObservableObject {
    @Published private(set) var snapshot: TelemetryConsentModel.Snapshot
    private let model: TelemetryConsentModel
    private let onChange: (TelemetryConsentModel.Snapshot) -> Void

    init(model: TelemetryConsentModel, onChange: @escaping (TelemetryConsentModel.Snapshot) -> Void) {
        self.model = model
        self.onChange = onChange
        snapshot = model.snapshot()
    }

    func refresh() { snapshot = model.snapshot() }

    func setAnalyticsEnabled(_ enabled: Bool) {
        let current = model.snapshot().choices
        save(.init(analyticsEnabled: enabled, diagnosticsEnabled: current.diagnosticsEnabled))
    }

    func setLocalDiagnosticsEnabled(_ enabled: Bool) {
        let current = model.snapshot().choices
        save(.init(analyticsEnabled: current.analyticsEnabled, diagnosticsEnabled: enabled))
    }

    func disableAll() { save(.off) }

    private func save(_ choices: TelemetryConsentModel.Choices) {
        let updated = model.setChoices(choices)
        snapshot = updated
        onChange(updated)
        // A caller may synchronously change context or close a gate while applying
        // the result. The UI must reflect that authoritative state too.
        snapshot = model.snapshot()
    }
}
