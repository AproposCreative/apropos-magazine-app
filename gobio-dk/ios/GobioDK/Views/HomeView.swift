import SwiftUI
import SDWebImageSwiftUI

struct HomeView: View {
    @EnvironmentObject var viewModel: MovieViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                
                if viewModel.isLoading {
                    ProgressView("Henter film...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    if !viewModel.nowPlayingMovies.isEmpty {
                        movieSection(title: "I biografen nu", movies: viewModel.nowPlayingMovies)
                    }
                    
                    if !viewModel.upcomingMovies.isEmpty {
                        movieSection(title: "Kommer snart", movies: viewModel.upcomingMovies, showBadge: true)
                    }
                    
                    if !viewModel.popularMovies.isEmpty {
                        movieSection(title: "Populære film", movies: viewModel.popularMovies)
                    }
                }
            }
            .padding(.bottom, 100)
        }
        .background(Color(hex: "0F0F23"))
        .refreshable {
            await viewModel.loadInitialData()
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 0) {
                        Text("gobio")
                            .font(.title.bold())
                            .foregroundColor(Color(hex: "818CF8"))
                        Text(".dk")
                            .font(.title.bold())
                            .foregroundColor(Color(hex: "F59E0B"))
                    }
                    
                    Text("Din danske biografguide")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                CitySelectorButton(selectedCity: viewModel.selectedCity) { city in
                    viewModel.updateCity(city)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
    
    private func movieSection(title: String, movies: [Movie], showBadge: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
                .foregroundColor(.white)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(movies) { movie in
                        NavigationLink(value: movie) {
                            MovieCardView(movie: movie, showUpcomingBadge: showBadge)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct CitySelectorButton: View {
    let selectedCity: String
    let onSelect: (String) -> Void
    @State private var showPicker = false
    
    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(Color(hex: "6366F1"))
                Text(selectedCity)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                List(danishCities, id: \.self) { city in
                    Button {
                        onSelect(city)
                        showPicker = false
                    } label: {
                        HStack {
                            Text(city)
                                .foregroundColor(.primary)
                            Spacer()
                            if city == selectedCity {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color(hex: "6366F1"))
                            }
                        }
                    }
                }
                .navigationTitle("Vælg by")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Luk") { showPicker = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}
