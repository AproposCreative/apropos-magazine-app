import SwiftUI

struct ArticleListView: View {
    @EnvironmentObject var viewModel: ArticleViewModel
    @State private var showFavorites = false
    @Environment(\.colorScheme) private var colorScheme
    // Remove the showStarsTest state

    var logoName: String {
        colorScheme == .dark ? "AproposLogoWhite" : "AproposLogoBlack"
    }

    var body: some View {
        NavigationStack {
            VStack {
                HStack {
                    Button(action: { showFavorites = false }) {
                        Label("Alle artikler", systemImage: showFavorites ? "doc.text" : "doc.text.fill")
                            .font(.body.weight(.semibold))
                            .foregroundColor(showFavorites ? .primary : Color("Accent"))
                    }
                    .padding(.trailing, 8)
                    Button(action: { showFavorites = true }) {
                        Label("Favoritter", systemImage: showFavorites ? "heart.fill" : "heart")
                            .font(.body.weight(.semibold))
                            .foregroundColor(showFavorites ? Color("Accent") : .primary)
                    }
                    Spacer()
                }
                .padding([.top, .horizontal])
                
                if let error = viewModel.fetchError {
                    VStack {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.red)
                            .padding(.bottom, 8)
                        Text(error)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                        Spacer()
                    }
                } else if viewModel.isLoading {
                    VStack {
                        Spacer()
                        ProgressView("Henter artikler...")
                            .progressViewStyle(CircularProgressViewStyle())
                            .padding()
                        Spacer()
                    }
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        // Add StarsTestView at the top for testing
                        StarsTestView()
                            .padding(.bottom, 16)
                        ScrollView {
                            LazyVStack(spacing: 24) {
                                ForEach(showFavorites ? viewModel.favorites : viewModel.articles) { article in
                                    NavigationLink(destination: ArticleDetailView(article: article)) {
                                        ArticleCardView(article: article)
                                            .environmentObject(viewModel)
                                    }
                                }
                            }
                            .padding()
                            
                            if !showFavorites {
                                VStack(alignment: .leading, spacing: 16) {
                                    if viewModel.isLoadingAI {
                                        HStack {
                                            ProgressView("AI genererer anbefalinger...")
                                                .progressViewStyle(CircularProgressViewStyle())
                                                .padding(.vertical, 16)
                                            Spacer()
                                        }
                                        .padding(.horizontal)
                                    } else if let aiError = viewModel.aiError {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack(spacing: 8) {
                                                Image(systemName: "exclamationmark.triangle.fill")
                                                    .foregroundColor(.red)
                                                Text(aiError)
                                                    .foregroundColor(.red)
                                            }
                                            Button(action: {
                                                viewModel.fetchAIRecommendations()
                                            }) {
                                                Label("Prøv igen", systemImage: "arrow.triangle.2.circlepath")
                                                    .font(.subheadline.bold())
                                                    .padding(8)
                                                    .background(Color.red.opacity(0.12))
                                                    .cornerRadius(8)
                                            }
                                        }
                                        .padding(.horizontal)
                                    } else if !viewModel.aiRecommendations.isEmpty {
                                        HStack(spacing: 8) {
                                            Text("🔮")
                                                .font(.title2)
                                                .padding(6)
                                                .background(Color.purple.opacity(0.15))
                                                .clipShape(Circle())
                                            Text("AI anbefaler")
                                                .font(.title2.weight(.semibold))
                                        }
                                        .padding(.horizontal)
                                        .padding(.top, 32)
                                        
                                        Button(action: {
                                            viewModel.fetchAIRecommendations()
                                        }) {
                                            Label("Få nye forslag", systemImage: "arrow.triangle.2.circlepath")
                                                .font(.subheadline.bold())
                                                .padding(8)
                                                .background(Color.purple.opacity(0.12))
                                                .cornerRadius(8)
                                        }
                                        .padding(.horizontal)
                                        
                                        ForEach(viewModel.aiRecommendations) { article in
                                            NavigationLink(destination: Text(article.title)) {
                                                ArticleCardView(article: article)
                                                    .environmentObject(viewModel)
                                            }
                                        }
                                    }
                                }
                                .padding(.bottom)
                            }
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image(logoName)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 32)
                        .accessibilityLabel("Apropos logo")
                }
                // Remove the toolbar button
            }
            // Remove the sheet presentation
            .navigationBarTitleDisplayMode(.inline)
            .background(Color("Background"))
        }
    }
}
