import SwiftUI

struct CollapsingTopBarContainer: View {
    let headerHeight: CGFloat
    let threshold: CGFloat
    let header: () -> AnyView
    let topBar: (_ progress: CGFloat) -> AnyView
    let content: () -> AnyView

    @State private var offset: CGFloat = 0
    @State private var didHaptic = false

    init<Header: View, Content: View, TopBar: View>(
        headerHeight: CGFloat = 320,
        threshold: CGFloat = 160,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder topBar: @escaping (_ progress: CGFloat) -> TopBar,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.headerHeight = headerHeight
        self.threshold = threshold
        self.header = { AnyView(header()) }
        self.topBar = { progress in AnyView(topBar(progress)) }
        self.content = { AnyView(content()) }
    }

    private var progress: CGFloat {
        // 0 → 1 når man har scrollet "threshold"
        let p = min(max(offset / threshold, 0), 1)
        return 1 - pow(1 - p, 3) // ease-out
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: true) {
                GeometryReader { geo in
                    let y = geo.frame(in: .global).minY
                    Color.clear
                        .preference(key: OffsetKey.self, value: -y)
                }
                .frame(height: 0)

                // Header (parallax)
                GeometryReader { geo in
                    let y = geo.frame(in: .global).minY
                    header()
                        .frame(height: headerHeight + max(0, -y * 0.25))
                        .offset(y: max(0, -y * 0.30))
                        .clipped()
                }
                .frame(height: headerHeight)

                // Indhold
                content()
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
            }
            .background(Color(.systemBackground))
            .onPreferenceChange(OffsetKey.self) { newValue in
                offset = newValue
                if progress > 0.999, !didHaptic {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    didHaptic = true
                } else if progress < 0.95 {
                    didHaptic = false
                }
            }

            // Topbar med blur + logo
            topBar(progress)
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(progress)
                        .overlay(Divider().opacity(0.25 * progress), alignment: .bottom)
                        .shadow(color: .black.opacity(0.08 * progress), radius: 10, y: 6)
                )
                .ignoresSafeArea(edges: .top)
        }
        .ignoresSafeArea(edges: .top)
    }
}

private struct OffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
