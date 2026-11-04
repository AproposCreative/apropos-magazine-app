import SwiftUI

/// Shared by the active Settings row and the local account fixture. The value
/// comes from the committed profile authority, never from a separate UI cache.
struct ProfileAccountSummary: View {
    let snapshot: UserProfileState.Snapshot

    private var profile: UserProfile? {
        guard let uid = snapshot.context.userID, snapshot.profile?.uid == uid else { return nil }
        return snapshot.profile
    }

    private var title: String {
        if let profile {
            let name = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Din konto" : name
        }
        switch snapshot.context {
        case .unresolved: return "Kontrollerer din konto"
        case .guest: return "Log ind eller opret en bruger"
        case .account: return "Din konto"
        }
    }

    private var status: String? {
        if let error = snapshot.errorMessage { return error }
        if snapshot.isLoading { return "Henter din profil…" }
        switch snapshot.context {
        case .unresolved: return "Profilen vises, når kontoen er bekræftet."
        case .guest: return "Synk dine gemte artikler på tværs af enheder"
        case .account: return profile == nil ? "Profilen er endnu ikke indlæst." : nil
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            avatar.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if let profile, !profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(verbatim: title)
                    } else {
                        Text(LocalizedStringKey(title))
                    }
                }
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("profile.summary.name")
                if let email = profile?.email, !email.isEmpty {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("profile.summary.email")
                }
                if let status {
                    Text(LocalizedStringKey(status))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("profile.summary.status")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder private var avatar: some View {
        if let value = profile?.photoURL, let url = URL(string: value),
           url.scheme?.lowercased() == "https", url.host?.isEmpty == false {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .resizable().scaledToFit().foregroundStyle(.secondary)
            }
            .frame(width: 50, height: 50)
            .clipShape(Circle())
        } else {
            Image(systemName: profile == nil ? "person.crop.circle" : "person.crop.circle.fill")
                .resizable().scaledToFit()
                .foregroundStyle(.secondary)
                .frame(width: 50, height: 50)
        }
    }
}

/// Account identity is informational. Only guests need a route into sign-in;
/// profile recovery stays explicit instead of hiding an action behind the name.
struct SettingsAccountSection: View {
    let snapshot: UserProfileState.Snapshot
    let onLogin: () -> Void
    let onRetry: () -> Void

    var canRetryProfile: Bool {
        snapshot.context.userID != nil && !snapshot.isLoading
            && (snapshot.errorMessage != nil || !snapshot.loaded)
    }

    var body: some View {
        Section {
            if snapshot.context == .guest {
                Button(action: onLogin) {
                    HStack {
                        ProfileAccountSummary(snapshot: snapshot)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.signIn")
            } else {
                ProfileAccountSummary(snapshot: snapshot)
                    .padding(.vertical, 8)
                if canRetryProfile {
                    Button(action: onRetry) {
                        Text("Prøv igen")
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.retryProfile")
                }
            }
        }
    }
}

struct SettingsVersionFooter: View {
    var body: some View {
        Section {
            Text("Version \(Bundle.main.shortVersionString) (\(Bundle.main.buildVersionString))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("settings.appVersion")
        }
    }
}
