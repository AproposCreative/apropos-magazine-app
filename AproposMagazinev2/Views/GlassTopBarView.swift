import SwiftUI

struct GlassTopBarView: View {
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(0..<30) { i in
                        Text("Artikelindhold \(i + 1)")
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                    }
                }
                .padding()
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: ScrollOffsetPreferenceKey.self, value: geo.frame(in: .named("scroll")).minY)
                    }
                )
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
            }

            VStack {
                HStack {
                    Button(action: {}) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.primary)
                            .padding(10)
                            .background(Color.gray.opacity(0.2))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Text("APROPOS")
                        .font(.headline)
                        .bold()

                    Spacer()

                    Button(action: {}) {
                        Image(systemName: "plus")
                            .font(.title2)
                            .foregroundColor(.primary)
                            .padding(10)
                            .background(Color.gray.opacity(0.2))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal)
                .padding(.top, 60)
                .padding(.bottom, 8)
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(scrollOffset < -10 ? 1.0 : 0.0)
                )
                .animation(.easeInOut(duration: 0.3), value: scrollOffset)
                .shadow(color: scrollOffset < -10 ? .black.opacity(0.1) : .clear, radius: 8, y: 4)
            }
        }
        .ignoresSafeArea(edges: .top)
    }
}

// ScrollOffsetPreferenceKey is already defined in ScrollUtilities.swift

// MARK: - Preview
struct GlassTopBarView_Previews: PreviewProvider {
    static var previews: some View {
        GlassTopBarView()
    }
}
