#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import UIKit
import FirebaseCore

/// A real navigation stack and the shared renderer/back policy, with only
/// local prose and state. No live ArticleViewModel, services or credentials.
struct LocalArticleBackSmokeView: View {
    @State private var path: [Int] = []
    @State private var appearances = 0
    @Namespace private var hero
    private var zoom: Bool { ProcessInfo.processInfo.arguments.contains("-AproposArticleBackZoom") }
    private var report: String {
        let value: [String: Any] = ["path": path, "depth": path.count,
            "appearances": appearances, "zoom": zoom, "firebaseStarted": FirebaseApp.allApps != nil]
        let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return String(decoding: data ?? Data(), as: UTF8.self)
    }
    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 24) {
                Text("Lokal artikelnavigation").font(.title2.bold())
                Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase startet")
                    .accessibilityIdentifier("article.back.fixture.firebase")
                Button("Åbn artikel") { path.append(1) }
                    .accessibilityIdentifier("article.back.fixture.open")
                    .matchedTransitionSource(id: 1, in: hero)
            }
            .navigationTitle("Artikler")
            .navigationDestination(for: Int.self) { index in destination(index) }
        }
        // Match the existing product's outside-stack enabler in the before run.
        .background(InteractivePopGestureEnabler())
        .overlay(alignment: .bottom) {
            Text("Lokal navigation · dybde \(path.count)")
                .font(.caption2).dynamicTypeSize(.large).padding(4)
                .background(Color(uiColor: .systemBackground))
                .accessibilityIdentifier("article.back.fixture.state")
                .accessibilityValue(report)
        }
        .tint(.primary)
    }
    @ViewBuilder private func destination(_ index: Int) -> some View {
        if zoom {
            reader(index).navigationTransition(.zoom(sourceID: index, in: hero))
        } else {
            reader(index)
        }
    }
    private func reader(_ index: Int) -> some View {
        LocalArticleBackReader(index: index, next: { path.append(index + 1) }, hero: hero)
            .onAppear { appearances += 1 }
    }
}

private struct LocalArticleBackReader: View {
    let index: Int
    let next: () -> Void
    let hero: Namespace.ID
    @Environment(\.dismiss) private var dismiss
    @State private var height: CGFloat = 240
    @StateObject private var load = ArticleHTMLLoadState()
    private var prose: String {
        (1...35).map { "<p>Lokalt afsnit \($0). Apropos fortæller om musik, kultur og mennesker. Denne tekst giver plads til rigtig rulning i den delte artikellæser. Ingen netværkskilder eller services bruges i prøven.</p>" }.joined()
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(0..<8) { item in
                            Text("Relateret \(item)")
                                .frame(width: 130, height: 70)
                                .background(Color.primary.opacity(0.08))
                        }
                    }.padding(.horizontal, 16)
                }
                .accessibilityIdentifier("article.back.fixture.carousel")
                Text("Artikel \(index)").font(.largeTitle.bold()).padding(.horizontal, 16)
                ArticleHTMLBody(html: prose, articleId: "article-back-\(index)", articleRevision: "1",
                    dynamicHeight: $height, loadState: load,
                    prepareHTML: { html, _ in .init(html: html, baseURL: nil) })
            }
        }
        .accessibilityIdentifier("article.back.fixture.scroll")
        .safeAreaInset(edge: .top) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Tilbage")
                .accessibilityIdentifier("article.back.fixture.button")
                Text("Apropos · Artikel \(index)").font(.headline)
                    .accessibilityIdentifier("article.back.fixture.header")
                Spacer()
                Button("Næste", action: next)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("article.back.fixture.next")
                    .matchedTransitionSource(id: index + 1, in: hero)
            }
            .padding(.horizontal, 16)
            .background(Color(uiColor: .systemBackground))
        }
        .overlay(alignment: .bottomLeading) {
            Text(load.phase == .ready ? "Artikel klar \(index)" : "Forbereder artikel \(index)")
                .font(.caption2).dynamicTypeSize(.large).padding(4)
                .background(Color(uiColor: .systemBackground))
                .accessibilityIdentifier("article.back.fixture.ready")
        }
        .background { ArticleBackNativeDiagnostic().frame(width: 1, height: 1).allowsHitTesting(false) }
        // Same stable article-owned policy as the live ArticleDetail host.
        .articleNativeBackNavigation()
    }
}

private struct ArticleBackNativeDiagnostic: UIViewRepresentable {
    func makeUIView(context: Context) -> ArticleBackDiagnosticLabel { ArticleBackDiagnosticLabel() }
    func updateUIView(_ uiView: ArticleBackDiagnosticLabel, context: Context) {}
}
private final class ArticleBackDiagnosticLabel: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityIdentifier = "article.back.fixture.native"
        accessibilityLabel = "Faktisk navigation"
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var accessibilityValue: String? {
        get {
            var responder: UIResponder? = self
            var navigation: UINavigationController?
            while let current = responder {
                if let controller = current as? UIViewController {
                    navigation = controller as? UINavigationController ?? controller.navigationController
                    if navigation != nil { break }
                }
                responder = current.next
            }
            let gesture = navigation?.interactivePopGestureRecognizer
            let value: [String: Any] = ["foundNavigation": navigation != nil,
                "stackDepth": navigation?.viewControllers.count ?? -1,
                "gestureEnabled": gesture?.isEnabled ?? false,
                "gestureState": gesture?.state.rawValue ?? -1,
                "gestureDelegate": gesture?.delegate.map { String(describing: type(of: $0)) } ?? "nil",
                "transitionActive": navigation?.transitionCoordinator != nil]
            let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            return String(decoding: data ?? Data(), as: UTF8.self)
        }
        set {}
    }
}
#endif
