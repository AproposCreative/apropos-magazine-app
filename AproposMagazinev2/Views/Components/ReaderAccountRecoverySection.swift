import SwiftUI

/// Status for the existing startup-owned recovery record. Rendering never reads
/// disk, constructs a provider, or begins a deletion request.
@MainActor
struct ReaderAccountRecoverySection: View {
    @ObservedObject var auth: AuthService
    var configuration: ReaderDeletionHTTPTransport.Configuration? = nil
    var googleService: GoogleSignInService? = nil
    var factory: AuthService.RecoveryFactory? = nil
    var supportedProviders: (@MainActor (AuthService.RecoveryTicket) -> Set<AuthService.RecoveryProvider>)? = nil
    @State private var choosingProvider: AuthService.RecoveryTicket?
    @State private var confirmation: Confirmation?
    @State private var rejectedPreparation: AuthService.RecoveryTicket?

    private struct Confirmation {
        let ticket: AuthService.RecoveryTicket
        let provider: AuthService.RecoveryProvider
        let configuration: ReaderDeletionHTTPTransport.Configuration
    }

    var body: some View {
        Group {
            if let flow = auth.accountRecoveryFlow {
                ReaderAccountRecoveryFlowSection(auth: auth, flow: flow, configuration: configuration)
                    .id(flow.id)
            } else {
            switch auth.accountRecoveryPresentation {
            case .checking:
                Section {
                    ProgressView("Kontrollerer din kontostatus…")
                        .accessibilityIdentifier("reader.recovery.checking")
                }
            case .unavailable:
                Section("Din konto") {
                    Text("Din kontostatus kunne ikke kontrolleres. Kontoadgangen forbliver lukket.")
                        .accessibilityIdentifier("reader.recovery.unavailable")
                    Text("Prøv at åbne appen igen. Ingen kontosletning er bekræftet her.")
                        .foregroundStyle(.secondary)
                }
            case .protected:
                Section("Din konto") {
                    Text("Kontoadgangen er beskyttet efter en tidligere handling.")
                        .accessibilityIdentifier("reader.recovery.protected")
                    Text("Der er ingen anmodning, som kan genoptages her. Kontosletning er ikke bekræftet.")
                        .foregroundStyle(.secondary)
                }
            case .deletion(let ticket):
                deletion(ticket)
            }
            }
        }
        .tint(.primary)
        .confirmationDialog("Bekræft med din eksisterende loginmetode", isPresented: Binding(
            get: { choosingProvider != nil }, set: { if !$0 { choosingProvider = nil } }),
            titleVisibility: .visible, presenting: choosingProvider) { ticket in
                Button("E-mail og adgangskode") { choose(.email, ticket: ticket) }
                Button("Apple") { choose(.apple, ticket: ticket) }
                Button("Google") { choose(.google, ticket: ticket) }
                Button("Annuller", role: .cancel) { choosingProvider = nil }
            } message: { _ in
                Text("Vælg den metode, der allerede er knyttet til din konto.")
            }
        .alert("Genoptag din anmodning?", isPresented: Binding(
            get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            presenting: confirmation) { original in
                Button("Genoptag") { begin(original) }
                    .accessibilityIdentifier("reader.recovery.confirm")
                Button("Annuller", role: .cancel) { confirmation = nil }
            } message: { _ in
                Text("Du skal bekræfte din identitet igen. Vi kontrollerer den tidligere anmodning om fjernelse af læserdata. Det er ikke en bekræftelse på, at hele kontoen er slettet.")
            }
        .onChange(of: configuration) { _, _ in choosingProvider = nil; confirmation = nil }
        .onChange(of: auth.accountRecoveryPresentation) { _, presentation in
            if let original = choosingProvider,
               presentation != .deletion(original) { choosingProvider = nil }
            if let original = confirmation,
               presentation != .deletion(original.ticket) { confirmation = nil }
        }
    }

    @ViewBuilder
    private func deletion(_ ticket: AuthService.RecoveryTicket) -> some View {
            Section("Fortsæt din anmodning") {
                Text("Der er en tidligere anmodning om fjernelse af læserdata. Den er ikke bekræftet afsluttet.")
                    .accessibilityIdentifier("reader.recovery.deletion")
                if auth.canPrepareAccountRecovery(ticket: ticket, configuration: configuration) {
                    Text("Bekræft din identitet igen for at kontrollere status. Kontoadgangen forbliver lukket imens.")
                        .foregroundStyle(.secondary)
                    if let rejected = rejectedPreparation, rejected.context == ticket.context,
                       rejected.checkpoint.isSameFamily(as: ticket.checkpoint) {
                        Text("Den valgte metode kunne ikke bruges til denne anmodning. Vælg din eksisterende loginmetode, og prøv igen.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("reader.recovery.providerUnavailable")
                    }
                    Button { choosingProvider = ticket } label: {
                        Text("Genoptag anmodning")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("reader.recovery.begin")
                } else {
                    Text("Anmodningen kan ikke genoptages lige nu. Den gemte status bevares.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("reader.recovery.notConfigured")
                }
            }
    }

    private func choose(_ provider: AuthService.RecoveryProvider, ticket: AuthService.RecoveryTicket) {
        choosingProvider = nil
        guard case .deletion(let current) = auth.accountRecoveryPresentation, current == ticket,
              let configuration, auth.canPrepareAccountRecovery(ticket: ticket, configuration: configuration) else { return }
        confirmation = Confirmation(ticket: ticket, provider: provider, configuration: configuration)
    }
    private func begin(_ original: Confirmation) {
        confirmation = nil
        guard configuration == original.configuration,
              case .deletion(let current) = auth.accountRecoveryPresentation, current == original.ticket else { return }
        guard let flow = auth.prepareAccountRecovery(ticket: original.ticket, provider: original.provider,
                configuration: original.configuration, googleService: googleService,
                supportedProviders: supportedProviders, factory: factory) else {
            rejectedPreparation = original.ticket
            return
        }
        rejectedPreparation = nil
        _ = auth.confirmAccountRecovery(flow, configuration: configuration, userConfirmed: true)
    }
}

@MainActor
private struct ReaderAccountRecoveryFlowSection: View {
    @ObservedObject var auth: AuthService
    let flow: AuthService.RecoveryFlow
    let configuration: ReaderDeletionHTTPTransport.Configuration?
    @ObservedObject private var coordinator: ReaderAccountDeletionCoordinator
    @State private var confirmation: Confirmation?
    private enum Confirmation: Equatable {
        case resume, ledger, pushRetry
        case push(ReaderAccountDeletionCoordinator.PushConfirmation)
        case localFavorites(ReaderAccountDeletionCoordinator.LocalFavoritesConfirmation)
        case localResume(ReaderAccountDeletionCoordinator.LocalResumeConfirmation)
        case localPodcast(ReaderAccountDeletionCoordinator.LocalPodcastConfirmation)
        case localIntroduction(ReaderAccountDeletionCoordinator.LocalIntroductionConfirmation)
        case localHistory(ReaderAccountDeletionCoordinator.LocalHistoryConfirmation)
    }

    init(auth: AuthService, flow: AuthService.RecoveryFlow,
         configuration: ReaderDeletionHTTPTransport.Configuration?) {
        self.auth = auth; self.flow = flow; self.configuration = configuration
        _coordinator = ObservedObject(wrappedValue: flow.coordinator)
    }
    private var isCurrent: Bool { auth.accountRecoveryFlow?.id == flow.id }
    private var canUse: Bool { auth.canUseAccountRecoveryFlow(flow, configuration: configuration) }

    var body: some View {
        Group {
            if isCurrent {
                Section("Din tidligere anmodning") {
                    Text(LocalizedStringKey(coordinator.message ?? "Bekræft din identitet for at genoptage anmodningen om læserdata."))
                        .accessibilityIdentifier("reader.recovery.status")
                    if !canUse {
                        Text("Genoptagelse er ikke tilgængelig med den aktuelle opsætning. Den tidligere anmodning bevares.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("reader.recovery.notConfigured")
                    } else if coordinator.hasPhysicalFlight
                                && coordinator.localFavoritesStatus != .preparing
                                && coordinator.localFavoritesStatus != .removing
                                && coordinator.localResumeStatus != .preparing
                                && coordinator.localResumeStatus != .removing
                                && coordinator.localPodcastStatus != .preparing
                                && coordinator.localPodcastStatus != .removing
                                && coordinator.localIntroductionStatus != .preparing
                                && coordinator.localIntroductionStatus != .removing
                                && coordinator.localHistoryStatus != .preparing
                                && coordinator.localHistoryStatus != .removing
                                && coordinator.pushStatus != .readingInstallation
                                && coordinator.pushStatus != .preparing
                                && coordinator.pushStatus != .retiring {
                        if coordinator.isWorking {
                            ProgressView(LocalizedStringKey(coordinator.status == .submitting ? "Kontrollerer anmodningen…" : "Afventer bekræftelse…"))
                        } else {
                            Text("Afventer afslutningen af den igangværende handling. Prøv igen, når den er afsluttet.")
                                .foregroundStyle(.secondary)
                        }
                    } else if coordinator.canBeginLedgerCleanup {
                        Button { confirmation = .ledger } label: {
                            Text("Fortsæt oprydningen")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .accessibilityIdentifier("reader.recovery.ledger")
                    } else if coordinator.canRetry || coordinator.status == .idle || coordinator.status == .cancelled {
                        Button { confirmation = .resume } label: {
                            Text(LocalizedStringKey(coordinator.canRetry ? "Prøv igen" : "Genoptag anmodning"))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .accessibilityIdentifier("reader.recovery.retry")
                    }
                    if coordinator.status != .cancelled && coordinator.status != .ledgerDataRemoved {
                        Button { auth.cancelAccountRecovery(flow) } label: {
                            Text("Annuller denne handling")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .accessibilityIdentifier("reader.recovery.cancel")
                    }
                }
                if canUse && (coordinator.canPreparePushRetirement || coordinator.canRetryPushRetirement
                    || coordinator.pushStatus != .idle) {
                    pushSection
                }
                if canUse && (coordinator.canPrepareLocalFavoritesCleanup || coordinator.localFavoritesStatus != .idle) {
                    localFavoritesSection
                }
                if canUse && coordinator.localFavoritesStatus == .removed
                    && (coordinator.canPrepareLocalResumeCleanup || coordinator.localResumeStatus != .idle) {
                    localResumeSection
                }
                if canUse && coordinator.localResumeStatus == .removed
                    && (coordinator.canPrepareLocalPodcastCleanup || coordinator.localPodcastStatus != .idle) {
                    localPodcastSection
                }
                if canUse && coordinator.localPodcastStatus == .removed
                    && (coordinator.canPrepareLocalIntroductionCleanup || coordinator.localIntroductionStatus != .idle) {
                    localIntroductionSection
                }
                if canUse && coordinator.localIntroductionStatus == .removed
                    && (coordinator.canPrepareLocalHistoryCleanup || coordinator.localHistoryStatus != .idle) {
                    localHistorySection
                }
            }
        }
        .alert(confirmationTitle,
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            presenting: confirmation) { original in
                Button("Bekræft") { confirm(original) }
                    .accessibilityIdentifier("reader.recovery.confirm")
                Button("Annuller", role: .cancel) {
                    if case .push = original { auth.cancelAccountRecoveryPush(flow) }
                    if case .pushRetry = original { auth.cancelAccountRecoveryPush(flow) }
                    if case .localFavorites = original { auth.cancelAccountRecoveryLocalFavorites(flow) }
                    if case .localResume = original { auth.cancelAccountRecoveryLocalResume(flow) }
                    if case .localPodcast = original { auth.cancelAccountRecoveryLocalPodcast(flow) }
                    if case .localIntroduction = original { auth.cancelAccountRecoveryLocalIntroduction(flow) }
                    if case .localHistory = original { auth.cancelAccountRecoveryLocalHistory(flow) }
                    confirmation = nil
                }
            } message: { original in
                switch original {
                case .push:
                    Text("Luk push for denne kontos bekræftede installation. Denne installation kan ikke tilmeldes push igen bagefter. Du skal bekræfte din identitet igen. Andre enheder og Research bevares. Allerede afsendte eller igangsatte beskeder kan ikke tilbagekaldes. Historiske pushdata og øvrige kontodata er ikke omfattet. Hele kontosletningen er fortsat uafsluttet.")
                case .pushRetry:
                    Text("Prøv den samme anmodning igen med ny bekræftelse af din identitet. Et tidligere forsøg kan allerede være gennemført. Vi bruger den oprindelige installation og samme bekræftede oplysninger. Ingen ny installation vælges. Hele kontosletningen er fortsat uafsluttet.")
                case .localFavorites:
                    Text("Fjern denne kontos gemte artikelvalg fra enheden. Andre kontis valg og Research bevares. Downloadede artikler, andre enheder og de øvrige kontodata er ikke omfattet. Kontosletningen er fortsat ikke gennemført.")
                case .localResume:
                    Text("Fjern denne kontos gemte læsepositioner fra enheden. Andre kontis og gæstens positioner samt Research bevares. Læsehistorik i iCloud, lyttepositioner, downloads og øvrige kontodata er ikke omfattet. Kontosletningen er fortsat ikke gennemført.")
                case .localPodcast:
                    Text("Fjern denne kontos gemte lyttepositioner fra enheden. Andre kontis og gæstens positioner samt Research bevares. Downloadet lyd, downloadede artikler, iCloud og øvrige kontodata er ikke omfattet. Kontosletningen er fortsat ikke gennemført.")
                case .localIntroduction:
                    Text("Fjern denne kontos introduktionsudkast på enheden. En gennemført introduktion, andre kontis udkast, gæstevalg og Research bevares. Interesser gemt på kontoen, downloadet indhold, iCloud og øvrige kontodata er ikke omfattet. Kontosletningen er fortsat ikke gennemført.")
                case .localHistory:
                    Text("Fjern denne kontos læsehistorik, der er tilgængelig på enheden. Andre kontis og gæstens historik samt Research bevares. Kontrollen bekræfter kun resultatet på denne enhed. Fjernelse fra iCloud og andre enheder er ikke bekræftet. Kontosletningen er fortsat ikke gennemført.")
                case .ledger:
                    Text("Næste trin fjerner de tilhørende læseroplysninger. Du skal bekræfte din identitet igen. Andre data mangler fortsat, og hele kontoen er ikke slettet.")
                case .resume:
                    Text("Du skal bekræfte din identitet igen for at kontrollere den oprindelige anmodning. Hele kontosletningen er ikke bekræftet.")
                }
            }
        .onChange(of: configuration) { _, _ in confirmation = nil }
        .onChange(of: isCurrent) { _, current in if !current { confirmation = nil } }
        .onChange(of: coordinator.pushConfirmation) { _, value in
            guard isCurrent, canUse, coordinator.pushStatus == .ready, let value else {
                if case .push = confirmation { confirmation = nil }
                return
            }
            confirmation = .push(value)
        }
        .onChange(of: coordinator.pushStatus) { _, status in
            if status != .ready, case .push = confirmation { confirmation = nil }
            if !coordinator.canRetryPushRetirement, case .pushRetry = confirmation { confirmation = nil }
        }
        .onChange(of: coordinator.localFavoritesConfirmation) { _, value in
            guard isCurrent, canUse, coordinator.localFavoritesStatus == .ready, let value else {
                if case .localFavorites = confirmation { confirmation = nil }
                return
            }
            confirmation = .localFavorites(value)
        }
        .onChange(of: coordinator.localFavoritesStatus) { _, status in
            if status != .ready, case .localFavorites = confirmation { confirmation = nil }
        }
        .onChange(of: coordinator.localResumeConfirmation) { _, value in
            guard isCurrent, canUse, coordinator.localResumeStatus == .ready, let value else {
                if case .localResume = confirmation { confirmation = nil }
                return
            }
            confirmation = .localResume(value)
        }
        .onChange(of: coordinator.localResumeStatus) { _, status in
            if status != .ready, case .localResume = confirmation { confirmation = nil }
        }
        .onChange(of: coordinator.localPodcastConfirmation) { _, value in
            guard isCurrent, canUse, coordinator.localPodcastStatus == .ready, let value else {
                if case .localPodcast = confirmation { confirmation = nil }
                return
            }
            confirmation = .localPodcast(value)
        }
        .onChange(of: coordinator.localPodcastStatus) { _, status in
            if status != .ready, case .localPodcast = confirmation { confirmation = nil }
        }
        .onChange(of: coordinator.localIntroductionConfirmation) { _, value in
            guard isCurrent, canUse, coordinator.localIntroductionStatus == .ready, let value else {
                if case .localIntroduction = confirmation { confirmation = nil }
                return
            }
            confirmation = .localIntroduction(value)
        }
        .onChange(of: coordinator.localIntroductionStatus) { _, status in
            if status != .ready, case .localIntroduction = confirmation { confirmation = nil }
        }
        .onChange(of: coordinator.localHistoryConfirmation) { _, value in
            guard isCurrent, canUse, coordinator.localHistoryStatus == .ready, let value else {
                if case .localHistory = confirmation { confirmation = nil }
                return
            }
            confirmation = .localHistory(value)
        }
        .onChange(of: coordinator.localHistoryStatus) { _, status in
            if status != .ready, case .localHistory = confirmation { confirmation = nil }
        }
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .push: return "Luk push for denne installation?"
        case .pushRetry: return "Prøv samme anmodning igen?"
        case .localFavorites: return "Fjern gemte artikelvalg?"
        case .localResume: return "Fjern læsepositioner?"
        case .localPodcast: return "Fjern lyttepositioner?"
        case .localIntroduction: return "Fjern introduktionsudkast?"
        case .localHistory: return "Fjern lokal læsehistorik?"
        case .ledger: return "Fortsæt oprydningen?"
        default: return "Genoptag din anmodning?"
        }
    }

    @ViewBuilder
    private var pushSection: some View {
        Section("Push på denne installation") {
            if let message = coordinator.pushMessage {
                Text(LocalizedStringKey(message)).accessibilityIdentifier("reader.recovery.push.status")
            }
            switch coordinator.pushStatus {
            case .readingInstallation:
                ProgressView("Kontrollerer den gemte installation…")
                    .accessibilityIdentifier("reader.recovery.push.pending")
            case .preparing:
                ProgressView("Kontrollerer installationens pushstatus…")
                    .accessibilityIdentifier("reader.recovery.push.pending")
            case .retiring:
                ProgressView("Afventer svar om denne installation…")
                    .accessibilityIdentifier("reader.recovery.push.pending")
            case .ready:
                if let original = coordinator.pushConfirmation {
                    Text("Kontrollen har ikke lukket push. Det kræver din særskilte bekræftelse.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("reader.recovery.push.preparedOnly")
                    Button("Luk push for denne installation") { confirmation = .push(original) }
                        .frame(minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("reader.recovery.push.confirmation")
                }
            case .retired:
                Text("Kun denne installation er lukket. Andre enheder, historiske pushdata og øvrige kontodata er ikke omfattet. Igangsatte beskeder kan ikke tilbagekaldes. Hele kontosletningen er fortsat uafsluttet.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("reader.recovery.push.partial")
            case .idle, .awaitingRetry, .unavailable, .cancelled, .timedOut:
                if coordinator.canRetryPushRetirement {
                    Button("Prøv samme anmodning igen") { confirmation = .pushRetry }
                        .frame(minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("reader.recovery.push.retry")
                } else if coordinator.canPreparePushRetirement {
                    Button(LocalizedStringKey(coordinator.hasStoredPushCommit ? "Genoptag tidligere pushoprydning" : "Kontrollér denne installation")) {
                        _ = auth.prepareAccountRecoveryPush(flow, configuration: configuration)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("reader.recovery.push.begin")
                }
            }
            if coordinator.hasPhysicalFlight
                && [.readingInstallation, .preparing, .retiring].contains(coordinator.pushStatus) {
                Button("Annuller denne pushhandling") { auth.cancelAccountRecoveryPush(flow) }
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("reader.recovery.push.cancel")
            }
        }
    }
    @ViewBuilder
    private var localFavoritesSection: some View {
        Section("Gemte artikelvalg på denne enhed") {
            if let message = coordinator.localFavoritesMessage {
                Text(LocalizedStringKey(message)).accessibilityIdentifier("reader.recovery.localFavorites.status")
            }
            switch coordinator.localFavoritesStatus {
            case .preparing:
                ProgressView("Kontrollerer de gemte artikelvalg…")
                    .accessibilityIdentifier("reader.recovery.localFavorites.pending")
            case .removing:
                ProgressView("Fjerner gemte artikelvalg…")
                    .accessibilityIdentifier("reader.recovery.localFavorites.pending")
            case .removed:
                Text("Kontosletningen er fortsat ikke gennemført.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("reader.recovery.localFavorites.partial")
            case .ready:
                if let original = coordinator.localFavoritesConfirmation {
                    Button("Fjern denne kontos gemte artikelvalg fra enheden") {
                        confirmation = .localFavorites(original)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("reader.recovery.localFavorites.begin")
                }
            case .idle, .failed, .cancelled:
                if coordinator.canPrepareLocalFavoritesCleanup {
                    Button(LocalizedStringKey(coordinator.localFavoritesStatus == .failed ? "Prøv lokal oprydning igen" : "Fjern denne kontos gemte artikelvalg fra enheden")) {
                        _ = auth.prepareAccountRecoveryLocalFavorites(flow, configuration: configuration)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("reader.recovery.localFavorites.begin")
                }
            }
        }
    }
    @ViewBuilder
    private var localResumeSection: some View {
        Section("Læsepositioner på denne enhed") {
            if let message = coordinator.localResumeMessage {
                Text(LocalizedStringKey(message)).accessibilityIdentifier("reader.recovery.localResume.status")
            }
            switch coordinator.localResumeStatus {
            case .preparing:
                ProgressView("Kontrollerer de gemte læsepositioner…")
                    .accessibilityIdentifier("reader.recovery.localResume.pending")
            case .removing:
                ProgressView("Fjerner gemte læsepositioner…")
                    .accessibilityIdentifier("reader.recovery.localResume.pending")
            case .removed:
                Text("Kontosletningen er fortsat ikke gennemført.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("reader.recovery.localResume.partial")
            case .ready:
                if let original = coordinator.localResumeConfirmation {
                    Button("Fjern denne kontos gemte læsepositioner fra enheden") {
                        confirmation = .localResume(original)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("reader.recovery.localResume.begin")
                }
            case .idle, .failed, .cancelled:
                if coordinator.canPrepareLocalResumeCleanup {
                    Button(LocalizedStringKey(coordinator.localResumeStatus == .failed ? "Prøv læsepositionsoprydning igen" : "Fjern denne kontos gemte læsepositioner fra enheden")) {
                        _ = auth.prepareAccountRecoveryLocalResume(flow, configuration: configuration)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("reader.recovery.localResume.begin")
                }
            }
        }
    }
    @ViewBuilder
    private var localPodcastSection: some View {
        Section("Lyttepositioner på denne enhed") {
            if let message = coordinator.localPodcastMessage {
                Text(LocalizedStringKey(message)).accessibilityIdentifier("reader.recovery.localPodcast.status")
            }
            switch coordinator.localPodcastStatus {
            case .preparing:
                ProgressView("Kontrollerer de gemte lyttepositioner…")
                    .accessibilityIdentifier("reader.recovery.localPodcast.pending")
            case .removing:
                ProgressView("Fjerner gemte lyttepositioner…")
                    .accessibilityIdentifier("reader.recovery.localPodcast.pending")
            case .removed:
                Text("Kontosletningen er fortsat ikke gennemført.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("reader.recovery.localPodcast.partial")
            case .ready:
                if let original = coordinator.localPodcastConfirmation {
                    Button("Fjern denne kontos gemte lyttepositioner fra enheden") {
                        confirmation = .localPodcast(original)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("reader.recovery.localPodcast.begin")
                }
            case .idle, .failed, .cancelled:
                if coordinator.canPrepareLocalPodcastCleanup {
                    Button(LocalizedStringKey(coordinator.localPodcastStatus == .failed ? "Prøv lyttepositionsoprydning igen" : "Fjern denne kontos gemte lyttepositioner fra enheden")) {
                        _ = auth.prepareAccountRecoveryLocalPodcast(flow, configuration: configuration)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("reader.recovery.localPodcast.begin")
                }
            }
        }
    }
    @ViewBuilder
    private var localIntroductionSection: some View {
        Section("Introduktionsudkast på denne enhed") {
            if let message = coordinator.localIntroductionMessage {
                Text(LocalizedStringKey(message)).accessibilityIdentifier("reader.recovery.localIntroduction.status")
            }
            switch coordinator.localIntroductionStatus {
            case .preparing:
                ProgressView("Kontrollerer introduktionsudkastet…")
                    .accessibilityIdentifier("reader.recovery.localIntroduction.pending")
            case .removing:
                ProgressView("Fjerner introduktionsudkastet…")
                    .accessibilityIdentifier("reader.recovery.localIntroduction.pending")
            case .removed:
                Text("Kontosletningen er fortsat ikke gennemført.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("reader.recovery.localIntroduction.partial")
            case .ready:
                if let original = coordinator.localIntroductionConfirmation {
                    Button("Fjern denne kontos introduktionsudkast fra enheden") {
                        confirmation = .localIntroduction(original)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("reader.recovery.localIntroduction.begin")
                }
            case .idle, .failed, .cancelled:
                if coordinator.canPrepareLocalIntroductionCleanup {
                    Button(LocalizedStringKey(coordinator.localIntroductionStatus == .failed ? "Prøv oprydning af udkast igen" : "Fjern denne kontos introduktionsudkast fra enheden")) {
                        _ = auth.prepareAccountRecoveryLocalIntroduction(flow, configuration: configuration)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("reader.recovery.localIntroduction.begin")
                }
            }
        }
    }
    @ViewBuilder
    private var localHistorySection: some View {
        Section("Læsehistorik på denne enhed") {
            if let message = coordinator.localHistoryMessage {
                Text(LocalizedStringKey(message)).accessibilityIdentifier("reader.recovery.localHistory.status")
            }
            switch coordinator.localHistoryStatus {
            case .preparing:
                ProgressView("Kontrollerer den lokale læsehistorik…")
                    .accessibilityIdentifier("reader.recovery.localHistory.pending")
            case .removing:
                ProgressView("Fjerner den lokale læsehistorik…")
                    .accessibilityIdentifier("reader.recovery.localHistory.pending")
            case .removed:
                Text("Fjernelse fra iCloud og andre enheder er ikke bekræftet. Kontosletningen er fortsat uafsluttet.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("reader.recovery.localHistory.partial")
            case .ready:
                if let original = coordinator.localHistoryConfirmation {
                    Button("Fjern denne kontos læsehistorik fra enheden") {
                        confirmation = .localHistory(original)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("reader.recovery.localHistory.begin")
                }
            case .idle, .failed, .cancelled:
                if coordinator.canPrepareLocalHistoryCleanup {
                    Button(LocalizedStringKey(coordinator.localHistoryStatus == .failed ? "Prøv oprydning af historik igen" : "Fjern denne kontos læsehistorik fra enheden")) {
                        _ = auth.prepareAccountRecoveryLocalHistory(flow, configuration: configuration)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("reader.recovery.localHistory.begin")
                }
            }
        }
    }
    private func confirm(_ original: Confirmation) {
        confirmation = nil
        guard isCurrent, canUse else { return }
        switch original {
        case .push(let original):
            _ = auth.confirmAccountRecoveryPush(flow, confirmation: original, configuration: configuration, userConfirmed: true)
        case .pushRetry:
            _ = auth.retryAccountRecoveryPush(flow, configuration: configuration, userConfirmed: true)
        case .resume: _ = auth.confirmAccountRecovery(flow, configuration: configuration, userConfirmed: true)
        case .ledger: _ = auth.confirmAccountRecoveryLedger(flow, configuration: configuration, userConfirmed: true)
        case .localFavorites(let original):
            _ = auth.confirmAccountRecoveryLocalFavorites(flow, confirmation: original,
                configuration: configuration, userConfirmed: true)
        case .localResume(let original):
            _ = auth.confirmAccountRecoveryLocalResume(flow, confirmation: original,
                configuration: configuration, userConfirmed: true)
        case .localPodcast(let original):
            _ = auth.confirmAccountRecoveryLocalPodcast(flow, confirmation: original,
                configuration: configuration, userConfirmed: true)
        case .localIntroduction(let original):
            _ = auth.confirmAccountRecoveryLocalIntroduction(flow, confirmation: original,
                configuration: configuration, userConfirmed: true)
        case .localHistory(let original):
            _ = auth.confirmAccountRecoveryLocalHistory(flow, confirmation: original,
                configuration: configuration, userConfirmed: true)
        }
    }
}

/// Attach this host to the stable account content, outside the Form's lazy
/// Section rows. Changing status content must not replace its modal presenter.
@MainActor
struct ReaderAccountRecoveryPresentation: View {
    @ObservedObject var auth: AuthService
    var appleProviderFactory: AppleAuthorizationButton.Coordinator.ProviderFactory? = nil

    var body: some View {
        Group {
            if let flow = auth.accountRecoveryFlow {
                ReaderAccountRecoveryPromptSheets(auth: auth, flow: flow,
                    appleProviderFactory: appleProviderFactory)
                    .id(flow.id)
            } else {
                Color.clear.frame(width: 0, height: 0)
            }
        }
    }
}

/// Observe the same Auth-owned prompts across account-sheet dismissal/reopen.
/// An old modal teardown can only cancel its captured original challenge.
@MainActor
private struct ReaderAccountRecoveryPromptSheets: View {
    @ObservedObject var auth: AuthService
    let flow: AuthService.RecoveryFlow
    let appleProviderFactory: AppleAuthorizationButton.Coordinator.ProviderFactory?
    @ObservedObject private var email: ReaderEmailReauthenticationPrompt
    @ObservedObject private var apple: ReaderAppleReauthenticationPrompt
    @ObservedObject private var google: ReaderGoogleReauthenticationPrompt
    private enum Presented: Identifiable {
        case email(ReaderEmailReauthenticationPrompt.Presentation)
        case apple(ReaderAppleReauthenticationPrompt.Presentation)
        case google(ReaderGoogleReauthenticationPrompt.Presentation)
        var id: UUID {
            switch self { case .email(let value): return value.id
            case .apple(let value): return value.id
            case .google(let value): return value.id }
        }
    }
    init(auth: AuthService, flow: AuthService.RecoveryFlow,
         appleProviderFactory: AppleAuthorizationButton.Coordinator.ProviderFactory?) {
        self.auth = auth; self.flow = flow; self.appleProviderFactory = appleProviderFactory
        _email = ObservedObject(wrappedValue: flow.prompts.email)
        _apple = ObservedObject(wrappedValue: flow.prompts.apple)
        _google = ObservedObject(wrappedValue: flow.prompts.google)
    }
    private var presented: Presented? {
        guard auth.accountRecoveryFlow?.id == flow.id else { return nil }
        switch flow.provider {
        case .email: return email.presentation.map(Presented.email)
        case .apple: return apple.presentation.map(Presented.apple)
        case .google: return google.presentation.map(Presented.google)
        }
    }
    var body: some View {
        let original = presented
        return Color.clear.frame(width: 0, height: 0)
            .sheet(item: Binding(get: { presented }, set: { value in
                guard value == nil, let original else { return }
                switch original {
                case .email(let value): email.cancel(action: value.action)
                case .apple(let value): apple.cancel(action: value.action)
                case .google(let value): google.cancel(action: value.action)
                }
            })) { value in
                switch value {
                case .email(let presentation): ReaderEmailReauthenticationSheet(prompt: email, presentation: presentation)
                case .apple(let presentation): ReaderAppleReauthenticationSheet(prompt: apple, presentation: presentation,
                    providerFactory: appleProviderFactory)
                case .google(let presentation): ReaderGoogleReauthenticationSheet(prompt: google, presentation: presentation)
                }
            }
    }
}
