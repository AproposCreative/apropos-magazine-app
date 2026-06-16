import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Apropos Premium")
                            .font(.largeTitle.bold())

                        Text("Støt uafhængig kulturjournalistik og få ubegrænset adgang til artikler, offline-læsning og mere.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        paywallFeature("Ubegrænset læsning af premium-artikler")
                        paywallFeature("Gem og synkroniser på tværs af enheder")
                        paywallFeature("Offline-læsning og widgets")
                    }

                    if subscriptionManager.isSubscribed {
                        Label("Du har aktivt abonnement", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    } else if subscriptionManager.isLoading && subscriptionManager.products.isEmpty {
                        ProgressView("Henter abonnementer…")
                            .frame(maxWidth: .infinity)
                    } else if subscriptionManager.products.isEmpty {
                        Text("Abonnementer er ikke tilgængelige endnu. Tjek App Store Connect-konfigurationen.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(subscriptionManager.products, id: \.id) { product in
                                Button {
                                    Task { await subscriptionManager.purchase(product) }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(product.displayName)
                                                .font(.headline)
                                            Text(product.description)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.leading)
                                        }
                                        Spacer()
                                        Text(product.displayPrice)
                                            .font(.headline)
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.accentColor.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                                .disabled(subscriptionManager.isLoading)
                            }
                        }
                    }

                    if let error = subscriptionManager.lastError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button("Gendan køb") {
                        Task { await subscriptionManager.restorePurchases() }
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)

                    Text("Abonnementet fornyes automatisk, medmindre det opsiges senest 24 timer før periodens udløb. Administrer abonnement under Apple ID-indstillinger.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("Abonnement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Luk") { dismiss() }
                }
            }
            .task {
                await subscriptionManager.refresh()
            }
        }
    }

    private func paywallFeature(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline)
    }
}

struct SubscriptionPaywallCard: View {
    let onSubscribe: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Premium-artikel")
                .font(.title3.bold())

            Text("Abonner for at læse hele artiklen og støtte Apropos Magazine.")
                .font(.body)
                .foregroundStyle(.secondary)

            Button(action: onSubscribe) {
                Text("Se abonnement")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }
}
