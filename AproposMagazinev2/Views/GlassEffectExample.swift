import SwiftUI

// MARK: - Scroll Offset Preference Key
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Main View with Glass Effect
struct GlassEffectExample: View {
    @State private var scrollOffset: CGFloat = 0
    
    var body: some View {
        ZStack(alignment: .top) {
            // Main ScrollView Content
            ScrollView {
                VStack(spacing: 20) {
                    // Content that will scroll
                    ForEach(0..<50, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.3))
                            .frame(height: 100)
                            .overlay(
                                Text("Item \(index + 1)")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            )
                    }
                }
                .padding(.horizontal)
                .padding(.top, 120) // Space for top bar
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geometry.frame(in: .named("scroll")).minY
                            )
                    }
                )
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
            }
            
            // Glass Effect Top Bar
            VStack(spacing: 0) {
                // Safe area spacer
                Color.clear
                    .frame(height: UIApplication.shared.connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .first?.windows.first?.safeAreaInsets.top ?? 0)
                
                // Top bar content
                HStack {
                    Text("Glass Effect Demo")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button("Menu") {
                        // Menu action
                    }
                    .foregroundColor(.primary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(scrollOffset < -20 ? 1.0 : 0.0)
                )
                .animation(.easeInOut(duration: 0.3), value: scrollOffset)
            }
            .frame(maxWidth: .infinity)
            .zIndex(1)
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(.systemBackground))
    }
}

// MARK: - Preview
struct GlassEffectExample_Previews: PreviewProvider {
    static var previews: some View {
        GlassEffectExample()
    }
}
