#if DEBUG && targetEnvironment(simulator)
import Combine
import FirebaseCore
import SwiftUI
import UIKit

/// Blocks only the injected background mapping read, never the main thread.
/// Every possible image URL in this fixture is a local file, including fallback.
private final class LocalOfflineImageReadGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var held: Bool
    private var permits = 0
    private var reads = 0
    private var mainReads = 0
    private var observer: (@Sendable () -> Void)?
    init(held: Bool) { self.held = held }
    func setObserver(_ value: @escaping @Sendable () -> Void) {
        condition.lock(); observer = value; condition.unlock()
    }
    func beforeRead() {
        condition.lock()
        reads += 1
        let onMain = Thread.isMainThread
        if onMain { mainReads += 1 }
        let notify = observer
        condition.unlock()
        notify?()
        guard !onMain else { return }
        condition.lock()
        while held && permits == 0 { condition.wait() }
        if held { permits -= 1 }
        condition.unlock()
    }
    func releaseOne() {
        condition.lock(); permits += 1; condition.broadcast(); condition.unlock()
    }
    func releaseAll() {
        condition.lock(); held = false; condition.broadcast(); condition.unlock()
    }
    var counts: (reads: Int, mainReads: Int) {
        condition.lock(); defer { condition.unlock() }
        return (reads, mainReads)
    }
}

@MainActor
private final class LocalOfflineImageFixture: ObservableObject {
    enum Scenario: String { case heldCold, heldColdWide, localReady, replacement, accountRoundTrip, onlineUnrelatedEviction, warmReentry }
    @MainActor private final class Authority { var generation = UUID() }
    let scenario: Scenario
    let cache: OfflineArticleImageCache
    let articleID = "local-offline-image"
    let revision = "local-image-r1"
    let originalURL: URL
    @Published private(set) var ready = false
    @Published private(set) var coverState = "Afventer"
    @Published private(set) var rowState = "Afventer"
    @Published private(set) var lookupCount = 0
    @Published private(set) var mainLookupCount = 0
    @Published private(set) var loadingCount = 0
    @Published private(set) var preparingCount = 0
    @Published private(set) var decodedCount = 0
    @Published private(set) var fallbackCount = 0
    @Published private(set) var redraws = 0
    @Published private(set) var newGeneration = false
    @Published private(set) var unrelatedEpochChanged = false
    @Published private(set) var fixtureError = ""
    @Published private(set) var phaseSamples: [[String: Any]] = []
    private let gate: LocalOfflineImageReadGate
    private let authority: Authority
    private let directory: URL
    private let contentKey = String(repeating: "a", count: 64)
    private var replaced = false

    init() {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-OfflineImageScenario"), args.indices.contains(index + 1) {
            scenario = Scenario(rawValue: args[index + 1]) ?? .heldCold
        } else { scenario = .heldCold }
        let gate = LocalOfflineImageReadGate(held: scenario == .heldCold || scenario == .heldColdWide || scenario == .accountRoundTrip)
        let authority = Authority()
        self.gate = gate; self.authority = authority
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("offline-image-smoke-\(UUID().uuidString)", isDirectory: true)
        directory = root.appendingPathComponent("cache", isDirectory: true)
        originalURL = root.appendingPathComponent("original-magenta.png")
        let key = String(repeating: "a", count: 64)
        let online = scenario == .onlineUnrelatedEviction
        cache = OfflineArticleImageCache(cacheDirectory: directory,
            download: { _ in throw URLError(.unsupportedURL) }, online: { online },
            preparationAccess: { article, revision in
                let original = authority.generation
                guard article == "local-offline-image", revision == "local-image-r1" else {
                    return .init(contentKey: nil, generation: original, isCurrent: { false })
                }
                return .init(contentKey: key, generation: original,
                             isCurrent: { authority.generation == original })
            }, mappingReadObserver: { gate.beforeRead() })
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Self.png(.systemPink).write(to: originalURL, options: .atomic)
            try seedImage(blue: false, corrupt: scenario == .replacement)
            ready = true
        } catch { fixtureError = String(describing: error) }
        gate.setObserver { [weak self] in
            Task { @MainActor [weak self] in self?.refreshCounters() }
        }
    }

    deinit { gate.releaseAll() }
    func stop() { gate.releaseAll() }
    func redraw() { redraws += 1 }
    func releaseOne() { gate.releaseOne() }
    func releaseAll() { gate.releaseAll() }
    func mark(_ name: String) {
        guard scenario == .warmReentry, phaseSamples.count < 160 else { return }
        phaseSamples.append(["event": name, "uptime": ProcessInfo.processInfo.systemUptime])
    }
    func record(_ event: PreparedArticleImage.Event, cover: Bool) {
        let value: String
        switch event {
        case .preparing: preparingCount += 1; value = "Klargør"
        case .loading(let url):
            loadingCount += 1
            if url == originalURL { fallbackCount += 1 }
            value = "Indlæser: \(colorName(url))"
        case .loaded(let url):
            decodedCount += 1
            value = "Klar: \(colorName(url))"
        case .failed(let url): value = "Fejl: \(url.map(colorName) ?? "ingen kilde")"
        }
        mark((cover ? "cover:" : "favorite:") + value)
        if cover { if coverState != value { coverState = value } }
        else if rowState != value { rowState = value }
    }
    func replaceInvalidImage() {
        guard scenario == .replacement, !replaced else { return }
        replaced = true
        // Called only after both real loaders failed. No held cache worker exists.
        cache.removeContent(contentKey)
        do { try seedImage(blue: true, corrupt: false) }
        catch { fixtureError = String(describing: error) }
        redraws += 1
    }
    func evictUnrelatedContent() {
        guard scenario == .onlineUnrelatedEviction else { return }
        let oldEpoch = cache.displayGeneration
        cache.removeContent(String(repeating: "b", count: 64))
        unrelatedEpochChanged = cache.displayGeneration != oldEpoch
        redraws += 1
    }
    func roundTrip() {
        guard scenario == .accountRoundTrip, !newGeneration else { return }
        authority.generation = UUID() // B
        authority.generation = UUID() // A with new ownership, never the first lease.
        do { try seedImage(blue: true, corrupt: false) }
        catch { fixtureError = String(describing: error) }
        // Do not queue.sync an eviction while the intentionally held lookup owns
        // that queue. The injected lease changes the actual view's identity.
        newGeneration = true
    }
    private func refreshCounters() {
        let counts = gate.counts
        lookupCount = counts.reads; mainLookupCount = counts.mainReads
    }
    private func colorName(_ url: URL) -> String {
        if url == originalURL { return "magenta fallback" }
        if url.lastPathComponent.hasPrefix("2") { return "blå" }
        return scenario == .replacement ? "ugyldig lokal fil" : "grøn"
    }
    private func seedImage(blue: Bool, corrupt: Bool) throws {
        let target = directory.appendingPathComponent(contentKey, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let filename = String(repeating: blue ? "2" : "1", count: 64) + ".png"
        let size = scenario == .heldColdWide ? CGSize(width: 160, height: 90) : CGSize(width: 64, height: 64)
        let bytes = corrupt ? Data("Not an image".utf8) : Self.png(blue ? .systemBlue : .systemGreen, size: size)
        try bytes.write(to: target.appendingPathComponent(filename), options: .atomic)
        try JSONEncoder().encode([originalURL.absoluteString: filename])
            .write(to: target.appendingPathComponent("mapping.json"), options: .atomic)
    }
    private static func png(_ color: UIColor, size: CGSize = CGSize(width: 64, height: 64)) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            color.setFill(); context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill(); context.fill(CGRect(x: 12, y: 12, width: 14, height: 40))
        }
    }
}

/// Service-free route using the same lifecycle, local WebImage loader and frames
/// as the actual article cover and favorite thumbnail.
struct LocalOfflineImageSmokeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var fixture = LocalOfflineImageFixture()
    @State private var frames: [String: CGRect] = [:]
    @State private var imageInstance = 0
    @State private var showingProbeRoute = false
    private var report: String {
        let payload: [String: Any] = [
            "scenario": fixture.scenario.rawValue,
            "phaseSamples": fixture.phaseSamples,
            "imageInstance": imageInstance,
            "showingProbeRoute": showingProbeRoute,
            "environmentAccessibility": dynamicTypeSize.isAccessibilitySize,
            "systemAccessibility": UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory,
            "systemCategory": UIApplication.shared.preferredContentSizeCategory.rawValue,
            "frames": frames.mapValues { ["x": Double($0.minX), "y": Double($0.minY), "width": Double($0.width), "height": Double($0.height)] }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let result = String(data: data, encoding: .utf8) else { return "{}" }
        return result
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                diagnostics
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if fixture.ready {
                            PreparedArticleImage(articleID: fixture.articleID, revision: fixture.revision,
                                remoteURL: fixture.originalURL, style: .cover, cache: fixture.cache,
                                event: { fixture.record($0, cover: true) })
                                .frame(maxWidth: .infinity, minHeight: fixture.scenario == .warmReentry ? 120 : 220,
                                       maxHeight: fixture.scenario == .warmReentry ? 120 : 340)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { record("cover", $0) }
                                .padding(.horizontal, 16)
                            Text("Foto: Lokal fixture")
                                .font(.system(size: 12))
                                .foregroundColor(colorScheme == .dark ? Color(white: 0.67) : Color(white: 0.4))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { record("credit", $0) }
                                .padding(.horizontal, 16).padding(.top, -8)
                                .accessibilityIdentifier("offlineImage.credit")
                            HStack(alignment: .bottom, spacing: 16) {
                                PreparedArticleImage(articleID: fixture.articleID, revision: fixture.revision,
                                    remoteURL: fixture.originalURL, style: .favorite, cache: fixture.cache,
                                    event: { fixture.record($0, cover: false) })
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { record("thumbnail", $0) }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Historier til senere").font(.headline).lineLimit(2)
                                    Text("KULTUR").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { record("row", $0) }
                            .padding(.horizontal, 16)
                            if fixture.scenario == .warmReentry {
                                ArticleCardView_Enhanced(article: Article(id: "local-home-image", name: "Samme cover ved tilbagekomst",
                                    slug: "local-home-image", content: "", intro: "", topicID: "fixture-culture"),
                                    cardHeight: 120, showTopic: false, imageURL: fixture.originalURL)
                                    .frame(width: 220)
                                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { record("homeCard", $0) }
                                    .accessibilityIdentifier("offlineImage.actualHomeCard")
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                    .id(imageInstance)
                    .padding(.vertical, 16)
                }
                .accessibilityIdentifier("offlineImage.scroll")
            }
            .navigationTitle("Lokale artikelbilleder")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showingProbeRoute) {
                Text("Lokal artikel; vender automatisk tilbage")
                    .accessibilityIdentifier("offlineImage.reentryDestination")
                    .task {
                        try? await Task.sleep(for: .milliseconds(1800))
                        guard !Task.isCancelled else { return }
                        fixture.mark("navigationReturn")
                        showingProbeRoute = false
                    }
            }
        }
        .onDisappear { fixture.stop() }
    }
    private var diagnostics: some View {
        VStack(spacing: 3) {
            HStack {
                Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase startet")
                    .accessibilityIdentifier("offlineImage.firebase")
                Text(fixture.ready ? "Klar" : "FEJL: \(fixture.fixtureError)").accessibilityIdentifier("offlineImage.ready")
            }
            HStack {
                Text("Cover: \(fixture.coverState)").accessibilityIdentifier("offlineImage.coverState")
                Text("Række: \(fixture.rowState)").accessibilityIdentifier("offlineImage.rowState")
            }
            HStack {
                Text("Opslag: \(fixture.lookupCount)").accessibilityIdentifier("offlineImage.reads")
                Text("Main: \(fixture.mainLookupCount)").accessibilityIdentifier("offlineImage.mainReads")
                Text("Prepares: \(fixture.preparingCount)").accessibilityIdentifier("offlineImage.prepares")
            }
            HStack {
                Text("Starts: \(fixture.loadingCount)").accessibilityIdentifier("offlineImage.starts")
                Text("Decoded: \(fixture.decodedCount)").accessibilityIdentifier("offlineImage.decoded")
                Text("Fallback: \(fixture.fallbackCount)").accessibilityIdentifier("offlineImage.fallback")
            }
            HStack {
                Text(fixture.newGeneration ? "Ny A-generation" : "Oprindelig læser").accessibilityIdentifier("offlineImage.owner")
                Text("Gentegninger: \(fixture.redraws)").accessibilityIdentifier("offlineImage.redraws")
                Text("Geometri").accessibilityIdentifier("offlineImage.geometry").accessibilityValue(report)
            }
            if fixture.scenario == .onlineUnrelatedEviction {
                Text(fixture.unrelatedEpochChanged ? "Ny uvedkommende cache-epoke" : "Oprindelig cache-epoke")
                    .accessibilityIdentifier("offlineImage.cacheEpoch")
            }
            HStack {
                switch fixture.scenario {
                case .heldCold, .heldColdWide:
                    Button("Frigiv opslag", action: fixture.releaseAll).accessibilityIdentifier("offlineImage.releaseAll")
                case .localReady:
                    Button("Gentegn", action: fixture.redraw).accessibilityIdentifier("offlineImage.redraw")
                case .replacement:
                    Button("Erstat ugyldig fil", action: fixture.replaceInvalidImage).accessibilityIdentifier("offlineImage.replace")
                case .accountRoundTrip:
                    Button("A → B → A", action: fixture.roundTrip).accessibilityIdentifier("offlineImage.roundTrip")
                    Button("Frigiv første", action: fixture.releaseOne).accessibilityIdentifier("offlineImage.releaseOne")
                    Button("Frigiv alle", action: fixture.releaseAll).accessibilityIdentifier("offlineImage.releaseAll")
                case .onlineUnrelatedEviction:
                    Button("Fjern anden cachepost", action: fixture.evictUnrelatedContent)
                        .accessibilityIdentifier("offlineImage.evictUnrelated")
                case .warmReentry:
                    Button("Til artikel") {
                        fixture.mark("navigationAway")
                        showingProbeRoute = true
                    }.accessibilityIdentifier("offlineImage.navigateAway")
                    Button("Genskab covers") {
                        fixture.mark("recreationScheduled")
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(800))
                            guard !Task.isCancelled else { return }
                            fixture.mark("recreatedSameURLs")
                            imageInstance += 1
                        }
                    }.accessibilityIdentifier("offlineImage.recreate")
                }
            }
            .buttonStyle(.bordered)
        }
        .font(.caption).dynamicTypeSize(.large).padding(8)
        .frame(maxWidth: .infinity).background(.quaternary)
    }
    private func record(_ key: String, _ frame: CGRect) {
        if frames[key] != frame { frames[key] = frame }
    }
}
#endif
