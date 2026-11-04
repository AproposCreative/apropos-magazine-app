import SwiftUI

/// The same Figma-backed presentation is used in Min side, the save sheet and
/// the service-free native fixture. Provider operations belong to its wrapper.
struct GuestAccountWelcome<Providers: View>: View {
    var inline = false
    var isWorking = false
    var message: String?
    let onEmail: () -> Void
    let onSignIn: () -> Void
    @ViewBuilder let providers: () -> Providers
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ScaledMetric(relativeTo: .headline) private var actionHeight: CGFloat = 48

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 10) {
                    Text("Vi har en holdning.\nFå din egen.")
                        .font(.largeTitle.bold()).multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("guestAccount.title")
                    Text("Opret en gratis konto, læs alt indhold offline og lyt til alle lydepisoder i højeste kvalitet.")
                        .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 10) {
                        providers()
                        Button(action: onEmail) {
                            HStack(spacing: 12) {
                                Image(systemName: "envelope").font(.system(size: 20))
                                    .frame(width: 24, height: 24).accessibilityHidden(true)
                                Text("Opret med e-mail").font(.headline).frame(maxWidth: .infinity)
                                Color.clear.frame(width: 24, height: 1)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .frame(minHeight: max(48, actionHeight))
                            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray, lineWidth: 0.7))
                        }
                        .buttonStyle(.plain).accessibilityLabel("Opret med e-mail")
                        .accessibilityIdentifier("guestAccount.email")
                        Button(action: onSignIn) {
                            Text("Har du allerede en konto? Log ind")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("guestAccount.signIn")
                    }
                    .padding(.top, 10).disabled(isWorking)
                    if isWorking {
                        ProgressView("Indlæser din samling…").padding(.top, 12)
                            .accessibilityIdentifier("guestAccount.working")
                    }
                    if let message {
                        Text(LocalizedStringKey(message)).font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("guestAccount.error")
                    }
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 24)
                .padding(.top, dynamicType.isAccessibilitySize ? 24 : inline ? geometry.size.height * 0.18 : 80)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("guestAccount.scroll")
        }
        .foregroundStyle(.white).environment(\.colorScheme, .dark)
    }
}
