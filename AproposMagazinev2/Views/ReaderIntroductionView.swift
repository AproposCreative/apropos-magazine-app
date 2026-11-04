import SwiftUI

/// Shared introduction UI. Persistence belongs to the injected local model;
/// account presentation stays above this persistent introduction/background.
struct ReaderIntroductionView: View {
    @ObservedObject var model: ReaderIntroductionModel
    let topics: [Topic]
    let isLoadingTopics: Bool
    let topicsError: String?
    let isGuest: Bool
    @Binding var language: ArticleContentLanguage
    let welcomeColorScheme: ColorScheme
    var accountContextGeneration: UUID? = nil
    let onRetryTopics: () -> Void
    let onCaptureInterests: ([String]) -> (@MainActor () async -> Bool)?
    let onFinish: () -> Void
    let onDefer: () -> Void
    let onAccount: (ReaderAccountEntry) -> Void
    var accountButtons: (() -> AnyView)? = nil
    var accountIsWorking = false
    var signedInEmail: String? = nil
    var onSignOut: () -> String? = { "Du kunne ikke logges ud. Prøv igen." }
    var newsletterStatus: ReaderNewsletterSignupModel.Status = .idle
    var newsletterMessage: String? = nil
    var onNewsletterSignup: () -> Bool = { false }
    var onNewsletterRetry: () -> Bool = { false }
    var savedInterestsError: String? = nil
    var onRetrySavedInterests: () -> Void = {}
    var newsletterCanReconfirm = false
    var onNewsletterReconfirm: () -> Bool = { false }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .headline) private var providerButtonHeight: CGFloat = 48
    @State private var pendingDestination: PendingDestination?
    @State private var failedInterestsRevision: UUID?
    @State private var newsletterOptIn = false
    @State private var newsletterAttempted = false
    @State private var newsletterStartFailed = false
    @State private var newsletterNeedsFreshChoice = false
    @State private var interestsWorking = false
    @State private var signOutError: String?
    @State private var welcomeAccountChoice: WelcomeAccountChoice?
    @AccessibilityFocusState private var titleIsFocused: Bool
    @AccessibilityFocusState private var errorIsFocused: Bool

    private enum Destination { case magazine, account(ReaderAccountEntry) }
    private enum WelcomeAccountChoice: Equatable { case signIn, signUp }
    private struct PendingDestination {
        let destination: Destination
        let revision: UUID
    }

    private var stepNumber: Int {
        switch model.step {
        case .welcome: 0
        case .interests: 1
        case .account: 2
        }
    }

    private var canEdit: Bool { model.hasLoaded && model.isPresented && !model.isSaving && !accountIsWorking && !interestsWorking }
    private var availableTopics: [Topic] { topics.filter(\.isActive) }

    var body: some View {
        ZStack {
            ReaderIntroductionBackdrop(isPresented: model.isPresented && model.step != .welcome)
                .opacity(model.step == .welcome ? 0 : 1)
            if model.step == .welcome { Color("Background").ignoresSafeArea() }
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                          if model.step == .welcome {
                            welcome(viewport: geometry.size).id("introduction.top")
                          } else {
                            header.id("introduction.top")
                            Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 20 : model.step == .welcome ? 44 : 24)
                            VStack(alignment: .leading, spacing: 24) {
                                if let error = model.storageError { storageError(error).id("introduction.error") }
                                if failedInterestsRevision == model.snapshot.revision {
                                    interestsStorageError.id("introduction.error")
                                }
                                Group {
                                    switch model.step {
                                    case .welcome: EmptyView()
                                    case .interests: interests
                                    case .account: account
                                    }
                                }
                                .disabled(!canEdit)
                            }
                            if model.step != .welcome {
                                footer.padding(.top, 20).disabled(!canEdit)
                            }
                          }
                        }
                        .frame(maxWidth: 560, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                        .frame(minHeight: geometry.size.height, alignment: .top)
                        .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("introduction.scroll")
                    .onChange(of: model.step) { _, _ in
                        // Only foreground content changes. The shared background
                        // remains mounted and retains its current animation phase.
                        proxy.scrollTo("introduction.top", anchor: .top)
                        welcomeAccountChoice = nil
                        titleIsFocused = true
                    }
                    .onChange(of: welcomeAccountChoice) { _, _ in
                        proxy.scrollTo("introduction.top", anchor: .top)
                        titleIsFocused = true
                    }
                    .onChange(of: model.storageError) { _, error in
                        if error != nil {
                            proxy.scrollTo("introduction.error", anchor: .top)
                            errorIsFocused = true
                        }
                    }
                    .onChange(of: failedInterestsRevision) { _, revision in
                        if revision != nil, revision == model.snapshot.revision {
                            proxy.scrollTo("introduction.error", anchor: .top)
                            errorIsFocused = true
                        }
                    }
                }
            }
        }
        .foregroundStyle(Color.primary)
        .environment(\.colorScheme, introductionColorScheme)
        .preferredColorScheme(introductionColorScheme)
        .interactiveDismissDisabled()
        .onChange(of: newsletterStatus) { _, status in
            if newsletterAttempted && (status == .subscribed || status == .alreadySubscribed) {
                finish(.magazine)
            } else if newsletterAttempted && status == .reconfirmationRequired && !newsletterCanReconfirm {
                // A spent/expired/unknown challenge never silently creates or
                // redeems another. The same form offers a new unchecked choice.
                newsletterOptIn = false
                newsletterAttempted = false
                newsletterNeedsFreshChoice = true
            }
        }
        .onChange(of: accountContextGeneration) { _, _ in
            // A different account epoch cannot inherit a marketing choice or
            // a retryable provider handoff made in the previous one.
            newsletterOptIn = false
            newsletterAttempted = false
            newsletterStartFailed = false
            newsletterNeedsFreshChoice = false
            pendingDestination = nil
            failedInterestsRevision = nil
            welcomeAccountChoice = nil
            if isGuest { signOutError = nil }
        }
    }

    private var header: some View {
        Image("AproposLogoWhite")
            .resizable().scaledToFit().frame(height: 30).opacity(0.9)
            .frame(maxWidth: .infinity).frame(height: 60)
            .accessibilityLabel("Apropos Magazine")
    }

    private var isWelcomeLanding: Bool { model.step == .welcome && welcomeAccountChoice == nil }
    // Read the presenting page's appearance, never this cover's own last
    // preferred scheme. Clearing a dark preference with nil can stay dark.
    private var introductionColorScheme: ColorScheme { isWelcomeLanding ? welcomeColorScheme : .dark }

    private func welcome(viewport: CGSize) -> some View {
        let choosingAccount = welcomeAccountChoice != nil
        let artworkHeight = dynamicTypeSize.isAccessibilitySize ? 180 :
            min(max(180, viewport.height - 470), max(180, viewport.width - 24))
        return VStack(alignment: .leading, spacing: 0) {
            welcomeHeader.disabled(!canEdit)
            if let error = model.storageError {
                storageError(error).id("introduction.error").padding(.top, 16)
            }
            title(choosingAccount ? (welcomeAccountChoice == .signIn ? "Log ind" : "Opret konto") :
                "Hvad er du nysgerrig på?\nLog ind, og find din næste historie.", id: "introduction.welcome.title", font: .title.bold())
                .padding(.top, 20).padding(.bottom, 20)

            // The same Apropos blue/white drawing is framed as artwork here.
            // Keep its identity while the provider choice is open; paused time
            // does not advance or restart its existing active-time clock.
            ReaderIntroductionBackdrop(isPresented: model.isPresented && !choosingAccount, isArtwork: true)
                .frame(height: choosingAccount ? 0 : artworkHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.trailing, -24)
                .opacity(choosingAccount ? 0 : 1)

            if !choosingAccount {
                magazinePill.disabled(!canEdit)
                Spacer(minLength: 24)
            }
            welcomeAccountActions.disabled(!canEdit)
        }
        .padding(.top, 8)
        .frame(minHeight: max(0, viewport.height - 24), alignment: .top)
    }

    private var welcomeHeader: some View {
        HStack(spacing: 16) {
            Image(introductionColorScheme == .dark ? "AproposLogoWhite" : "AproposLogoBlack")
                .resizable().scaledToFit().frame(width: 112, height: 44)
                .accessibilityLabel("Apropos Magazine")
                .accessibilityIdentifier("introduction.welcome.logo")
            Spacer(minLength: 0)
            Menu {
                ForEach(ArticleContentLanguage.allCases, id: \.self) { value in
                    Button { language = value } label: {
                        if language == value { Label(value.displayName, systemImage: "checkmark") }
                        else { Text(verbatim: value.displayName) }
                    }
                    .accessibilityIdentifier("introduction.language.\(value.rawValue)")
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "globe").font(.title3).accessibilityHidden(true)
                    Text(verbatim: language.rawValue.uppercased()).font(.callout)
                }
                .padding(.horizontal, 8).frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Sprog")
            .accessibilityValue(Text(verbatim: language.displayName))
            .accessibilityIdentifier("introduction.language")
        }
    }

    @ViewBuilder private var welcomeAccountActions: some View {
      if (isGuest || accountIsWorking) && welcomeAccountChoice == nil {
        VStack(spacing: 12) {
            landingButton("Log ind", filled: true, id: "introduction.welcome.signIn") { welcomeAccountChoice = .signIn }
            landingButton("Opret konto", filled: false, id: "introduction.welcome.signUp") { welcomeAccountChoice = .signUp }
        }
      } else {
        VStack(spacing: 16) {
            if isGuest || accountIsWorking {
                VStack(spacing: 10) {
                    if let accountButtons { accountButtons() }
                    else {
                        ReaderIntroductionAppleButton { openAccount(.apple) }
                            .frame(height: max(48, providerButtonHeight))
                        providerButton("Fortsæt med Google", symbol: nil, provider: .google)
                    }
                    if welcomeAccountChoice == .signIn {
                        providerButton("Log ind med e-mail", symbol: "envelope", provider: .emailSignIn)
                    } else {
                        providerButton("Opret med e-mail", symbol: "envelope", provider: .emailSignUp)
                    }
                    guestButton("Tilbage", id: "introduction.welcome.back") { welcomeAccountChoice = nil }
                    magazinePill
                }.padding(.top, 10)
            } else {
                VStack(spacing: 10) {
                    Group {
                        if let email = signedInEmail { Text("Du er logget ind som \(email)") }
                        else { Text("Du er allerede logget ind.") }
                    }
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("introduction.account.current")
                    landingButton("Fortsæt med din konto", filled: true, id: "introduction.account.continue") { advance() }
                    guestButton("Log ud og vælg en anden konto", id: "introduction.account.signOut") {
                        signOutError = onSignOut()
                    }
                    if let signOutError {
                        Text(LocalizedStringKey(signOutError)).font(.subheadline)
                            .accessibilityIdentifier("introduction.account.signOut.error")
                    }
                }.padding(.top, 10)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
      }
    }

    private func landingButton(_ label: String, filled: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(LocalizedStringKey(label)).font(.headline)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20).padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: max(48, providerButtonHeight))
                .foregroundStyle(filled ? (introductionColorScheme == .dark ? Color.black : .white) : Color.primary)
                .background(filled ? Color.primary : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary, lineWidth: filled ? 0 : 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }

    private var interests: some View {
        VStack(alignment: .leading, spacing: 24) {
            title("Hvad er du nysgerrig på?", id: "introduction.interests.title")
            bodyText("Vælg det, du gerne vil læse mere om.")

            if model.isAwaitingSavedInterests {
                VStack(alignment: .leading, spacing: 8) {
                    if let savedInterestsError {
                        Text(LocalizedStringKey(savedInterestsError)).font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("introduction.interests.saved.error")
                        Button("Prøv igen", action: onRetrySavedInterests)
                            .frame(minHeight: 44).buttonStyle(.plain)
                            .accessibilityIdentifier("introduction.interests.saved.retry")
                    } else if model.storageError == nil {
                        HStack(alignment: .top, spacing: 10) {
                            ProgressView().accessibilityHidden(true)
                            Text("Henter dine gemte interesser…").font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }.accessibilityIdentifier("introduction.interests.saved.loading")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                if isLoadingTopics {
                    HStack(alignment: .top, spacing: 12) {
                        ProgressView().accessibilityHidden(true)
                        Text("Henter emner…").fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("introduction.topics.loading")
                }
                if topicsError != nil {
                    Text("Emnerne kunne ikke hentes. Prøv igen, eller vælg dem senere.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("introduction.topics.error")
                    Button("Prøv igen", action: onRetryTopics)
                        .frame(minHeight: 44).buttonStyle(.plain)
                        .accessibilityIdentifier("introduction.topics.retry")
                } else if availableTopics.isEmpty && !isLoadingTopics {
                    Text("Der er ingen emner at vælge lige nu. Du kan fortsætte og vælge senere på Min side.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("introduction.topics.empty")
                }
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(availableTopics) { topic in topicButton(topic) }
                    }
                } else {
                    ReaderIntroductionWordLayout {
                        ForEach(availableTopics) { topic in topicButton(topic) }
                    }
                }
                if model.selectedTopicIDs.count >= 20 {
                    Text("Du har valgt 20 emner. Fjern et valg, hvis du vil vælge et andet.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("introduction.topics.limit")
                }
            }

        }
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 24) {
            title("Historier i din indbakke.", id: "introduction.account.title")
            bodyText("Få Apropos’ historier og anbefalinger på e-mail. Du kan altid afmelde dig.")
            Toggle(isOn: Binding(get: { newsletterOptIn }, set: {
                pendingDestination = nil
                newsletterOptIn = $0
            })) {
                Text("Ja tak, send mig Apropos’ nyhedsbrev.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(ReaderIntroductionCheckboxStyle())
            .accessibilityIdentifier("introduction.newsletter.choice")
            .accessibilityValue(Text(LocalizedStringKey(newsletterOptIn ? "Valgt" : "Ikke valgt")))
            .disabled(newsletterAttempted)
            if newsletterAttempted || newsletterNeedsFreshChoice, let newsletterMessage {
                Text(LocalizedStringKey(newsletterMessage)).font(.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("introduction.newsletter.status")
            }
            if newsletterStartFailed {
                Text("Tilmeldingen kunne ikke startes. Du kan prøve igen på Min side.")
                    .font(.body).foregroundStyle(.secondary)
                    .accessibilityIdentifier("introduction.newsletter.error")
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if model.step != .welcome {
              HStack(spacing: 6) {
                ForEach(1...2, id: \.self) { number in
                    Capsule().fill(Color.primary.opacity(number == stepNumber ? 1 : 0.3))
                        .frame(width: number == stepNumber ? 28 : 5, height: 5)
                }
            }
            .frame(maxWidth: .infinity).frame(height: 28)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tilpasning, trin \(stepNumber) af 2")
            .accessibilityIdentifier("introduction.step")
            }

            if model.step == .interests {
                primaryButton(interestsWorking ? "Gemmer…" : "Fortsæt", id: "introduction.interests.continue") { commitInterests() }
                    .disabled(model.isAwaitingSavedInterests)
                guestButton("Vælg senere", id: "introduction.interests.skip") { model.advance() }
                backButton(compact: false)
            } else {
                if !newsletterAttempted {
                    primaryButton(newsletterOptIn ? "Tilmeld og fortsæt" : "Gå til magasinet", id: "introduction.finish") {
                        if newsletterOptIn { subscribe() } else { finish(.magazine) }
                    }
                } else if newsletterStatus == .reconfirmationRequired && newsletterCanReconfirm {
                    primaryButton("Tilmeld igen", id: "introduction.newsletter.reconfirm") { _ = onNewsletterReconfirm() }
                } else if newsletterStatus == .unavailable || newsletterStatus == .pending {
                    primaryButton("Prøv igen", id: "introduction.newsletter.retry") { _ = onNewsletterRetry() }
                }
                if newsletterAttempted {
                    guestButton("Gå til magasinet", id: "introduction.newsletter.continue") { finish(.magazine) }
                } else {
                    backButton(compact: false)
                }
            }
        }
    }

    private var magazinePill: some View {
        Button { finish(.magazine, skipping: true) } label: {
            HStack(spacing: 8) {
                Text("Udforsk magasinet").fixedSize(horizontal: false, vertical: true)
                Image(systemName: "arrow.right").accessibilityHidden(true)
            }
            .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier("introduction.skip")
    }

    private func backButton(compact: Bool) -> some View {
        Button {
            pendingDestination = nil
            model.back()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left")
                if !compact { Text("Tilbage") }
            }
            .font(compact ? .title3 : .subheadline)
            .frame(minWidth: compact ? 48 : 44, minHeight: 48)
            .background(compact ? Color(uiColor: .secondarySystemBackground) : .clear,
                in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel("Tilbage")
        .accessibilityIdentifier("introduction.back")
    }

    private func guestButton(_ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(LocalizedStringKey(label)).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 48).frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }

    private func providerButton(_ label: String, symbol: String?, provider: ReaderAccountEntry.Provider) -> some View {
        Button { openAccount(provider) } label: {
            HStack(spacing: 12) {
                Group {
                    if let symbol { Image(systemName: symbol).font(.system(size: 20)) }
                    else { Image("GoogleSignInMark").resizable().scaledToFit().frame(width: 20, height: 20) }
                }
                .frame(width: 24).accessibilityHidden(true)
                Text(LocalizedStringKey(label)).font(.headline).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
                Color.clear.frame(width: 24, height: 1).accessibilityHidden(true)
            }
            .padding(.horizontal, 16).padding(.vertical, 11).frame(minHeight: 48)
            .foregroundStyle(provider == .google ? Color.black : Color.white)
            .background(provider == .google ? .white : Color(white: 0.12),
                in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.gray.opacity(0.6), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).accessibilityIdentifier("introduction.account.\(provider)")
    }

    private func openAccount(_ provider: ReaderAccountEntry.Provider) {
        let entry = ReaderAccountEntry(topicIDs: model.selectedTopicIDs, provider: provider)
        onAccount(entry)
    }

    private func title(_ value: String, id: String, font: Font = .largeTitle.bold()) -> some View {
        Text(LocalizedStringKey(value)).font(font)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($titleIsFocused)
            .accessibilityIdentifier(id)
    }

    private func bodyText(_ value: String) -> some View {
        Text(LocalizedStringKey(value)).font(.body).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func topicButton(_ topic: Topic) -> some View {
        let selected = model.selectedTopicIDs.contains(topic.id)
        return Button {
            pendingDestination = nil
            model.toggleTopic(topic.id)
        } label: {
            LocalizedArticleTaxonomy(topic.name).font(.title.weight(.semibold))
                .underline(selected).foregroundStyle(selected ? Color.primary : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .padding(.vertical, 6).frame(minWidth: 44, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!selected && model.selectedTopicIDs.count >= 20)
        .accessibilityLabel(Text(verbatim: AppLocalization.taxonomy(topic.name, language: AppLocalization.language(for: locale))))
        .accessibilityValue(Text(LocalizedStringKey(selected ? "Valgt" : "Ikke valgt")))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("introduction.topic.\(topic.id)")
    }

    private func primaryButton(_ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(LocalizedStringKey(label)).font(.headline).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 24)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .foregroundStyle(Color.black)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }

    private func storageError(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(message)).font(.body).fixedSize(horizontal: false, vertical: true)
                .accessibilityFocused($errorIsFocused)
                .accessibilityIdentifier("introduction.storage.error")
            Button("Prøv igen") {
                let pending = pendingDestination
                pendingDestination = nil
                let currentDestination = pending.flatMap { $0.revision == model.snapshot.revision ? $0.destination : nil }
                if model.retry() {
                    if let currentDestination { handOff(currentDestination) }
                    else if model.isCompleted && !model.isPresented { onFinish() }
                } else if let currentDestination, model.storageError != nil {
                    pendingDestination = PendingDestination(destination: currentDestination, revision: model.snapshot.revision)
                }
            }
            .font(.headline).frame(minHeight: 44).buttonStyle(.plain)
            .disabled(model.isSaving)
            .accessibilityIdentifier("introduction.storage.retry")
            Button {
                pendingDestination = nil
                onDefer()
            } label: {
                Text("Gå til magasinet uden at gemme")
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(model.isSaving)
            .accessibilityIdentifier("introduction.storage.defer")
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var interestsStorageError: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dine interesser kunne ikke gemmes. Prøv igen, eller vælg dem senere.")
                .font(.body).fixedSize(horizontal: false, vertical: true)
                .accessibilityFocused($errorIsFocused)
                .accessibilityIdentifier("introduction.interests.storage.error")
            Button("Prøv igen") {
                guard failedInterestsRevision == model.snapshot.revision else { return }
                commitInterests()
            }
            .font(.headline).frame(minHeight: 44).buttonStyle(.plain)
            .disabled(!canEdit)
            .accessibilityIdentifier("introduction.interests.storage.retry")
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func commitInterests() {
        guard !model.isAwaitingSavedInterests else { return }
        pendingDestination = nil
        failedInterestsRevision = nil
        let revision = model.snapshot.revision
        let ids = model.selectedTopicIDs
        guard let commit = onCaptureInterests(ids), revision == model.snapshot.revision, model.isPresented else {
            if revision == model.snapshot.revision, model.isPresented { failedInterestsRevision = revision }
            return
        }
        interestsWorking = true
        Task { @MainActor in
            guard revision == model.snapshot.revision, model.isPresented else { interestsWorking = false; return }
            let saved = await commit()
            interestsWorking = false
            guard revision == model.snapshot.revision, model.isPresented else { return }
            if saved { model.advance() }
            else { failedInterestsRevision = revision }
        }
    }

    private func subscribe() {
        newsletterNeedsFreshChoice = false
        newsletterAttempted = true
        newsletterStartFailed = !onNewsletterSignup()
        if !newsletterStartFailed && (newsletterStatus == .subscribed || newsletterStatus == .alreadySubscribed) {
            finish(.magazine)
        }
    }

    private func advance() {
        pendingDestination = nil
        model.advance()
    }

    private func finish(_ destination: Destination, skipping: Bool = false) {
        pendingDestination = nil
        guard skipping ? model.skip() : model.complete() else {
            if model.storageError != nil {
                pendingDestination = PendingDestination(destination: destination, revision: model.snapshot.revision)
            }
            return
        }
        handOff(destination)
    }

    private func handOff(_ destination: Destination) {
        switch destination {
        case .magazine: onFinish()
        case .account(let entry): onAccount(entry)
        }
    }
}

private struct ReaderIntroductionCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(configuration.isOn ? Color.primary : Color(uiColor: .systemBackground))
                    RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary, lineWidth: 1.5)
                    if configuration.isOn {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(uiColor: .systemBackground))
                    }
                }
                .frame(width: 21, height: 21).padding(.top, 1).accessibilityHidden(true)
                configuration.label
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(LocalizedStringKey(configuration.isOn ? "Valgt" : "Ikke valgt")))
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}
