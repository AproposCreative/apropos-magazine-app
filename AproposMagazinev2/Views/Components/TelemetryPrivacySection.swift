import SwiftUI

/// Shared by the real settings form and the local, SDK-free simulator fixture.
struct TelemetryPrivacySection: View {
    @ObservedObject var controller: TelemetryConsentController
    @Environment(\.locale) private var locale

    var body: some View {
        Section {
            Text("Du bestemmer, om du vil dele brugsstatistik eller gemme en lokal teknisk log. Du kan bruge appen med begge valg slået fra.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("privacy.explanation")

            Toggle(isOn: Binding(get: { controller.snapshot.choices.analyticsEnabled }, set: controller.setAnalyticsEnabled)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Del brugsstatistik")
                        .font(.body.weight(.medium))
                    Text("Del brugshændelser og artikel-id'er med Firebase, når du læser, lytter eller bruger anbefalinger. Konto-id, titler og anbefalingstekster indgår ikke.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityIdentifier("privacy.analytics")

            Toggle(isOn: Binding(get: { controller.snapshot.choices.diagnosticsEnabled }, set: controller.setLocalDiagnosticsEnabled)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Lokal teknisk log")
                        .font(.body.weight(.medium))
                    Text("Gem en teknisk log til fejlsøgning på denne enhed. Den deles ikke automatisk. Valget giver ingen tilladelse til at sende crashrapporter til skyen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityIdentifier("privacy.crashReports")

            if let error = errorMessage {
                Text(LocalizedStringKey(error))
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("privacy.error")
            } else {
                Text(LocalizedStringKey(statusMessage))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("privacy.status")
            }

            Button(action: controller.disableAll) {
                Label("Slå begge fra", systemImage: "hand.raised")
            }
            .tint(.primary)
            .foregroundStyle(.primary)
            .accessibilityIdentifier("privacy.disableAll")

            if let url = NewsletterSignupPolicy.termsURL(for: AppLocalization.language(for: locale)) {
                Link("Privatliv og vilkår", destination: url)
                    .tint(.primary)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("privacy.terms")
            }
        } header: {
            Text("Privatliv")
        } footer: {
            Text("Valgene gælder på denne enhed. Login, nyhedsbrev, pushbeskeder og læsehistorik styres hver for sig.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var errorMessage: String? {
        switch controller.snapshot.state {
        case .writeFailed:
            return "Valget kunne ikke gemmes. Begge valg er slået fra i denne åbning af appen. En tidligere indstilling kan blive aktiv igen efter genstart. Prøv at slå begge fra igen."
        case .readFailed:
            return "Indstillingerne kunne ikke læses. Begge valg er slået fra i denne åbning af appen. Vælg på ny, eller prøv at slå begge fra."
        case .invalidRecord, .unsupportedVersion:
            return "De gemte indstillinger kan ikke bruges. Begge valg er slået fra. Vælg på ny, eller slå begge fra."
        case .invalidClock:
            return "Valget kunne ikke bekræftes. Begge valg er slået fra i denne åbning af appen. Prøv igen. En tidligere indstilling kan blive aktiv igen efter genstart."
        case .unloaded, .updating, .notChosen, .ready:
            return nil
        }
    }

    private var statusMessage: String {
        switch controller.snapshot.state {
        case .unloaded:
            return "Begge valg er slået fra, indtil indstillingerne er læst."
        case .updating:
            return "Begge valg er slået fra, mens dit valg gemmes."
        case .notChosen:
            return "Du har endnu ikke valgt. Begge valg er slået fra."
        case .ready:
            return "Dine valg er gemt på denne enhed. Du kan ændre dem når som helst."
        case .invalidRecord, .unsupportedVersion, .readFailed, .writeFailed, .invalidClock:
            return "Begge valg er slået fra."
        }
    }
}
