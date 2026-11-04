import SwiftUI

/// The real contact fields, also used by the SDK-free simulator fixture.
struct SupportContactSections: View {
    @ObservedObject var model: SupportContactModel

    var body: some View {
        Group {
            Section {
                Text("Skriv til os om appen. Du vælger selv Send i din mailapp; denne formular sender ikke en besked automatisk.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(SupportContactPolicy.recipient)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("support.address")
            } header: { Text("Kontakt Apropos") }

            Section {
                ZStack(alignment: .topLeading) {
                    if model.message.isEmpty {
                        Text("Skriv din besked …")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: Binding(get: { model.message }, set: model.updateMessage))
                        .frame(minHeight: 180)
                        .scrollContentBackground(.hidden)
                        .accessibilityLabel("Din besked")
                        .accessibilityIdentifier("support.message")
                }
                Button(action: model.openMailDraft) {
                    Label(LocalizedStringKey(isBusy ? "Åbner mailkladde …" : "Åbn mailkladde"), systemImage: "envelope")
                }
                .tint(.primary)
                .foregroundStyle(.primary)
                .disabled(isBusy)
                .accessibilityIdentifier("support.openDraft")
                Text(LocalizedStringKey(statusText))
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("support.status")
            } header: { Text("Din besked") } footer: {
                Text("Teksten bevares, mens dette vindue er åbent. Vi vedhæfter ikke kontooplysninger eller tekniske logs.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Button(action: model.copyAddress) {
                    Label("Kopiér e-mailadresse", systemImage: "doc.on.doc")
                }
                .tint(.primary)
                .foregroundStyle(.primary)
                .accessibilityIdentifier("support.copyAddress")
                Button(action: model.copyMessage) {
                    Label("Kopiér besked", systemImage: "doc.on.doc")
                }
                .tint(.primary)
                .foregroundStyle(.primary)
                .disabled(!SupportContactPolicy.isMeaningfulMessage(model.message))
                .accessibilityIdentifier("support.copyMessage")
                Text("Du kan også kopiere adressen og beskeden til din mailapp. Lange beskeder forkortes ikke.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: { Text("Andre muligheder") }
        }
    }

    private var isBusy: Bool { model.state == .composing || model.state == .openingMailApp }

    private var statusText: String {
        switch model.state {
        case .idle: return "Din besked bliver først sendt, når du selv vælger Send i mailkladden."
        case .emptyMessage: return "Skriv en besked, før du åbner mailkladden."
        case .composing: return "Mailkladden er åben. Du vælger selv, om den skal sendes, gemmes eller afbrydes."
        case .openingMailApp: return "Åbner din mailapp. Din tekst er bevaret her."
        case .handedToMail: return "Mail har lagt beskeden i kø til afsendelse. Modtagelse er ikke bekræftet. Din tekst er bevaret her."
        case .draftSaved: return "Mail har gemt kladden. Din tekst er også bevaret her."
        case .cancelled: return "Du afbrød mailkladden. Din tekst er bevaret her."
        case .composerFailed: return "Mail kunne ikke afslutte kladden. Din tekst er bevaret. Prøv igen, eller brug kopiknapperne."
        case .mailAppOpened: return "Fortsæt i din mailapp, og tjek modtager og besked. Afsendelse er ikke bekræftet. Din tekst er bevaret her."
        case .manualFallback: return "Mailkladden kunne ikke åbnes. Kopiér adressen og din besked til din mailapp. Din fulde tekst er bevaret her."
        case .openingTimedOut: return "Åbningen blev ikke bekræftet. Din tekst er bevaret. Prøv igen, eller brug kopiknapperne."
        case .addressCopied: return "E-mailadressen er kopieret."
        case .messageCopied: return "Beskeden er kopieret. Teksten står også stadig her."
        case .copyFailed: return "Kopieringen kunne ikke bekræftes. Din tekst er bevaret her. Prøv igen."
        }
    }
}
