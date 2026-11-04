#if DEBUG && targetEnvironment(simulator)
import Combine
import FirebaseCore
import SwiftUI
import UIKit

private final class LocalListenHeroDownloadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func attempted() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

/// Same seeded mapping and real file loader as LocalOfflineImageSmokeView.
/// No image work is started for the original default color-hero scenario.
@MainActor
private final class LocalListenHeroImageFixture: ObservableObject {
    enum Scenario: String { case loadedPortrait, loadedLandscape }
    let scenario: Scenario?
    let cache: OfflineArticleImageCache?
    let originalURL: URL?
    let cachedURL: URL?
    let pixelSize: CGSize
    let articleID = "listen-hero-local-article"
    let revision = "listen-hero-image-r1"
    private let downloads: LocalListenHeroDownloadCounter
    @Published private(set) var phase = "unused"
    @Published private(set) var loadedCount = 0
    @Published private(set) var failedCount = 0
    @Published private(set) var loadedFromSeededCache = false
    @Published private(set) var loadingLocalFile = false
    @Published private(set) var seedReady = false

    init() {
        let args = ProcessInfo.processInfo.arguments
        let selected: Scenario?
        if let index = args.firstIndex(of: "-ReaderListenHeroImage"), args.indices.contains(index + 1) {
            selected = Scenario(rawValue: args[index + 1])
        } else { selected = nil }
        scenario = selected
        let counter = LocalListenHeroDownloadCounter()
        downloads = counter
        guard let selected else {
            cache = nil; originalURL = nil; cachedURL = nil; pixelSize = .zero
            return
        }
        let size = selected == .loadedPortrait ? CGSize(width: 600, height: 900) : CGSize(width: 900, height: 600)
        pixelSize = size
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("listen-hero-image-\(UUID().uuidString)", isDirectory: true)
        let directory = root.appendingPathComponent("cache", isDirectory: true)
        let original = root.appendingPathComponent("original.png")
        let key = String(repeating: "a", count: 64), filename = String(repeating: "1", count: 64) + ".png"
        let target = directory.appendingPathComponent(key, isDirectory: true)
        originalURL = original; cachedURL = target.appendingPathComponent(filename)
        let lease = UUID()
        cache = OfflineArticleImageCache(cacheDirectory: directory,
            download: { _ in counter.attempted(); throw URLError(.unsupportedURL) }, online: { false },
            preparationAccess: { article, revision in
                guard article == "listen-hero-local-article", revision == "listen-hero-image-r1" else {
                    return .init(contentKey: nil, generation: lease, isCurrent: { false })
                }
                return .init(contentKey: key, generation: lease, isCurrent: { true })
            })
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let bytes = UIGraphicsImageRenderer(size: size, format: format).pngData { context in
                UIColor.systemTeal.setFill(); context.fill(CGRect(origin: .zero, size: size))
                UIColor.white.setFill()
                context.fill(CGRect(x: size.width * 0.2, y: size.height * 0.1,
                    width: size.width * 0.6, height: size.height * 0.8))
            }
            try bytes.write(to: original, options: .atomic)
            try bytes.write(to: target.appendingPathComponent(filename), options: .atomic)
            try JSONEncoder().encode([original.absoluteString: filename])
                .write(to: target.appendingPathComponent("mapping.json"), options: .atomic)
            seedReady = UIImage(data: bytes)?.size == size
            phase = seedReady ? "seeded" : "seed-failed"
        } catch { phase = "seed-failed" }
    }

    var downloadCount: Int { downloads.value }
    func record(_ event: PreparedArticleImage.Event) {
        switch event {
        case .preparing: phase = "preparing"
        case .loading(let url): phase = "loading"; loadingLocalFile = url.isFileURL
        case .loaded(let url):
            phase = "loaded"; loadedCount += 1
            loadedFromSeededCache = url.isFileURL && url == cachedURL
        case .failed: phase = "failed"; failedCount += 1
        }
    }
}

/// The production listen/hero stack children with a local catalog and artwork.
/// A native tap records only the ArticleListenAction callback, never playback.
@MainActor
struct LocalArticleListenHeroSmokeView: View {
    @StateObject private var catalog = PodcastCatalogPublication()
    @StateObject private var imageFixture = LocalListenHeroImageFixture()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var frames: [String: CGRect] = [:]
    @State private var actionCount = 0
    @State private var selectedEpisodeID: String?
    private let episode = PodcastEpisode(id: "listen-hero-local-recording", articleId: "listen-hero-local-article",
        articleSlug: "listen-hero-local-article", title: "En lokal artikel med en eksisterende lydversion",
        subtitle: nil, audioURL: URL(string: "https://example.invalid/not-requested.m4a"),
        productionSourceURL: nil, duration: nil, artworkURL: nil, hosts: [], publishedDate: nil)

    private var report: String {
        let payload: [String: Any] = [
            "actionCount": actionCount, "selectedEpisodeID": selectedEpisodeID ?? "none",
            "catalogCount": catalog.snapshot.episodes.count,
            "managerInvoked": false, "audioStarted": false,
            "firebaseStarted": FirebaseApp.allApps != nil,
            "environmentAccessibility": dynamicTypeSize.isAccessibilitySize,
            "systemAccessibility": UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory,
            "systemCategory": UIApplication.shared.preferredContentSizeCategory.rawValue,
            "chromeIsLocalFixture": true,
            "imageScenario": imageFixture.scenario?.rawValue ?? "default",
            "imagePhase": imageFixture.phase, "imageSeedReady": imageFixture.seedReady,
            "imageLoadedCount": imageFixture.loadedCount, "imageFailedCount": imageFixture.failedCount,
            "imageLoadedFromSeededCache": imageFixture.loadedFromSeededCache,
            "imageLoadingLocalFile": imageFixture.loadingLocalFile,
            "imageDownloadCount": imageFixture.downloadCount,
            "imagePixelWidth": Double(imageFixture.pixelSize.width),
            "imagePixelHeight": Double(imageFixture.pixelSize.height),
            "frames": frames.mapValues { rect in
                ["x": Double(rect.minX), "y": Double(rect.minY),
                 "width": Double(rect.width), "height": Double(rect.height)]
            }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Spacer().frame(height: 50)
                        Text("Musik").font(.system(size: 15, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .center)
                        ArticleHeaderTitle(text: "En fortælling om musik og mennesker", textColor: .primary)
                        ArticleHeaderSubtitle(text: "Den delte artikelknap og billedets faktiske placering.", textColor: .primary)
                        ArticleHeaderTagGroup(authorName: "Apropos", categories: ["Musik"], openAuthor: {}) { EmptyView() }
                            .padding(.horizontal, 16).padding(.top, 5)
                        ArticleListenHeroSection(catalog: catalog,
                            selection: { $0.snapshot.episodes.first }, title: { _ in "Lyt til artiklen" },
                            play: { current in
                                selectedEpisodeID = current.id
                                actionCount += 1
                            }) {
                            heroArtwork
                            .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 340)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { record("hero", $0) }
                            .padding(.horizontal, 16)
                            .accessibilityIdentifier("listenHero.hero")
                        }
                        Text("Kun lokal geometri og knaphandling. Ingen lyd eller tjenester startes.")
                            .font(.body).padding(.horizontal, 16)
                        Color.clear.frame(height: 220)
                    }
                }
                .accessibilityIdentifier("listenHero.scroll")
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { record("viewport", $0) }

                HStack {
                    Image(systemName: "chevron.left").frame(width: 32, height: 32)
                    Spacer()
                    Image("AproposLogoBlack").resizable().scaledToFit().frame(height: 30)
                    Spacer()
                    Color.clear.frame(width: 32, height: 32)
                }
                .padding(.horizontal, 16).frame(height: 60)
                .background(.regularMaterial)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { record("chrome", $0) }
                .accessibilityIdentifier("listenHero.chrome")
                .zIndex(1)
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottomLeading) {
                Text("Lokal artikelgeometri")
                    .font(.system(size: 1)).frame(width: 1, height: 1).opacity(0.01)
                    .accessibilityIdentifier("listenHero.report").accessibilityValue(report)
                    .allowsHitTesting(false)
            }
            .onAppear { catalog.replace([episode]) }
        }
        .tint(.primary)
    }

    private func record(_ key: String, _ frame: CGRect) {
        if frames[key] != frame { frames[key] = frame }
    }

    @ViewBuilder private var heroArtwork: some View {
        if imageFixture.scenario != nil, let cache = imageFixture.cache, let original = imageFixture.originalURL {
            PreparedArticleImage(articleID: imageFixture.articleID, revision: imageFixture.revision,
                remoteURL: original, style: .cover, cache: cache, event: { imageFixture.record($0) })
        } else {
            ZStack {
                Color(red: 0.06, green: 0.18, blue: 0.36)
                Image(systemName: "waveform")
                    .font(.system(size: 64)).foregroundStyle(.white)
            }
        }
    }
}
#endif
