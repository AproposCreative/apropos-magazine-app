#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import FirebaseCore
import UIKit

@MainActor
private final class LocalPodcastProgressFixture: ObservableObject {
    @Published var failWrites = false
    @Published private(set) var owner = "Uafklaret"
    @Published private(set) var contextChanges = 0
    private var oldTicket: PodcastPlaybackProgressStore.Ticket?
    let store: PodcastPlaybackProgressStore

    init() {
        // The box retains only this fixture's in-memory data. No defaults or
        // platform player is constructed, even after explicit test actions.
        let box = MemoryBox()
        self.box = box
        store = PodcastPlaybackProgressStore(storage: .init(read: { box.records[$0.storageKey] }, write: {
            if box.failWrites { throw MemoryBox.Failure.write }
            box.records[$0.storageKey] = $1
        }))
        store.onContextInvalidated = { [weak self] in self?.contextChanges += 1 }
    }
    private let box: MemoryBox
    private final class MemoryBox {
        enum Failure: Error { case write }
        var records: [String: Data] = [:]
        var failWrites = false
    }
    func select(_ value: String) {
        switch value {
        case "Konto A": store.changeContext(to: .confirmed(userID: "fixture-account-a"))
        case "Konto B": store.changeContext(to: .confirmed(userID: "fixture-account-b"))
        case "Gæst": store.changeContext(to: .guest)
        default: store.changeContext(to: .unresolved)
        }
        owner = value
    }
    func save() {
        box.failWrites = failWrites
        guard let session = store.beginSession(episodeID: "local-episode", articleID: "local-article") else { return }
        if owner == "Konto A" { oldTicket = session.ticket }
        store.save(session.ticket, seconds: 42, duration: 600)
    }
    func releaseOldSave() {
        guard let oldTicket else { return }
        store.save(oldTicket, seconds: 99, duration: 600)
    }
    func syncFailureFlag() { box.failWrites = failWrites }
}

@MainActor
struct LocalPodcastProgressSmokeView: View {
    @StateObject private var fixture = LocalPodcastProgressFixture()
    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("-AproposFullPlayerSmoke") {
            LocalFullPlayerSmokeView()
                .environment(\.podcastTitleReduceMotionOverride,
                    ProcessInfo.processInfo.arguments.contains("-AproposFullPlayerReduceMotion") ? true : nil)
        } else if ProcessInfo.processInfo.arguments.contains("-AproposPlayerTimelineSmoke") {
            LocalPlayerTimelineSmokeView()
        } else if ProcessInfo.processInfo.arguments.contains("-AproposMiniMotionSmoke") {
            LocalMiniPlayerMotionSmokeView()
        } else {
            LocalPodcastProgressContent(fixture: fixture, store: fixture.store)
        }
    }
}

/// The same complete presentation is mounted in a real large sheet. Platform
/// routing and artwork transport are inert local inputs, not service mocks.
private struct LocalFullPlayerSmokeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.podcastTitleReduceMotionOverride) private var titleReduceMotionOverride
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingPlayer = false
    @State private var showingQueue = false
    @State private var selectedIndex = 0
    @State private var position = 0.35
    @State private var isPlaying = false
    @State private var isLoading = ProcessInfo.processInfo.arguments.contains("-AproposFullPlayerNarratedSmoke")
    @State private var playActions = 0
    @State private var seekCommits = 0
    @State private var rateActions = 0
    @State private var queueOpens = 0
    @State private var queueSelections = 0
    @State private var backwardActions = 0
    @State private var forwardActions = 0
    @State private var shareActions = 0
    @State private var sleepActions = 0
    @State private var routeActions = 0
    @State private var frames: [String: CGRect] = [:]
    private let episodes: [PodcastEpisode] = [
        ("full-player-one", "Når musikken forandrer byen: en lang samtale om fællesskab, kultur og de mennesker, der holder fortællingerne levende"),
        ("full-player-two", "Nye perspektiver på det danske kulturliv")
    ].map { id, title in
        let args = ProcessInfo.processInfo.arguments
        let displayTitle: String
        if id == "full-player-one" && args.contains("-AproposFullPlayerTitleTraversalSmoke") {
            displayTitle = "Apropos Magazine · Film, musik og kultur"
        } else if id == "full-player-one" && args.contains("-AproposFullPlayerShortTitleSmoke") {
            displayTitle = "Et kort øjeblik"
        } else {
            displayTitle = title
        }
        return PodcastEpisode(id: id, articleId: nil, articleSlug: nil, title: displayTitle,
            subtitle: "Apropos Magazine · Redaktionel samtale", audioURL: nil,
            productionSourceURL: nil, duration: nil, artworkURL: nil,
            hosts: [], publishedDate: nil)
    }
    private let category = "MUSIK • KULTUR • MENNESKER OG FÆLLESSKAB"
    private let author = "Signe Jensen og Alexander Frederiksen fra Apropos Magazine"
    private var isNarrated: Bool { ProcessInfo.processInfo.arguments.contains("-AproposFullPlayerNarratedSmoke") }
    private var rateLabel: String { podcastPlaybackRateText([Float(1), 1.25, 1.5][rateActions % 3]) }
    private var foreground: Color { colorScheme == .dark ? .white : .primary }
    private var reduceMotion: Bool { titleReduceMotionOverride ?? systemReduceMotion }
    private var artworkVariant: Int {
        let args = ProcessInfo.processInfo.arguments
        let base = args.firstIndex(of: "-AproposCoverVariant").flatMap { index in
            index + 1 < args.count ? Int(args[index + 1]) : nil
        } ?? 0
        return (max(0, base) + selectedIndex) % Self.covers.count
    }
    // Generated once, fully local: warm, cool, bright, wide, tall,
    // low-luminance blue (owner reference), then missing artwork.
    private static let covers: [UIImage?] = [
        ([UIColor.systemOrange, .systemRed], CGSize(width: 256, height: 256)),
        ([.systemBlue, .systemTeal], CGSize(width: 256, height: 256)),
        ([.white, .systemYellow], CGSize(width: 256, height: 256)),
        ([.systemPurple, .systemPink], CGSize(width: 512, height: 192)),
        ([.systemGreen, .systemTeal], CGSize(width: 192, height: 512)),
        ([UIColor(red: 0.08, green: 0.22, blue: 0.33, alpha: 1),
          UIColor(red: 0.025, green: 0.035, blue: 0.05, alpha: 1)], CGSize(width: 256, height: 256))
    ].map { colors, size in
        UIGraphicsImageRenderer(size: size).image { renderer in
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors.map(\.cgColor) as CFArray, locations: [0, 1])!
            renderer.cgContext.drawLinearGradient(gradient, start: .zero,
                end: CGPoint(x: size.width, y: size.height), options: [])
            UIColor.black.withAlphaComponent(0.25).setFill()
            UIBezierPath(ovalIn: CGRect(x: 45, y: 35, width: 140, height: 140)).fill()
        }
    } + [nil]
    private var report: String {
        let value: [String: Any] = [
            "episodeID": episodes[selectedIndex].id, "title": episodes[selectedIndex].title,
            "category": category, "author": author, "isPlaying": isPlaying,
            "isLoading": isLoading, "isNarrated": isNarrated,
            "position": position, "playActions": playActions, "seekCommits": seekCommits,
            "rateActions": rateActions, "rateLabel": rateLabel, "queueOpens": queueOpens,
            "queueSelections": queueSelections, "backwardActions": backwardActions,
            "forwardActions": forwardActions, "shareActions": shareActions,
            "sleepActions": sleepActions, "routeActions": routeActions,
            "artworkVariant": artworkVariant, "firebaseStarted": FirebaseApp.allApps != nil,
            "dynamicType": String(describing: dynamicTypeSize), "reduceMotion": reduceMotion,
            "systemReduceMotion": systemReduceMotion,
            "reduceMotionSource": titleReduceMotionOverride == nil ? "system" : "title-only simulator override",
            "platformSlots": "local route button, generated local artwork, no volume slider",
            "frames": frames.mapValues { ["x": $0.minX, "y": $0.minY, "width": $0.width, "height": $0.height] }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase er startet")
                .accessibilityIdentifier("full.player.fixture.firebase")
            Button("Åbn fuld afspiller") { showingPlayer = true }
                .accessibilityIdentifier("full.player.fixture.open")
        }
        .sheet(isPresented: $showingPlayer) {
            GeometryReader { host in
                ZStack {
                    PodcastFullPlayerPresentation(
                    title: episodes[selectedIndex].title, category: category, author: author,
                    isAINarration: isNarrated, isLoading: isLoading, isPlaying: isPlaying,
                    sliderValue: $position, currentTimeLabel: "3:30", remainingTimeLabel: "-6:30",
                    playbackRateLabel: rateLabel,
                    onEditingChanged: { if !$0 { seekCommits += 1 } },
                    onCycleRate: { rateActions += 1 },
                    onBackward: { backwardActions += 1; position = max(0, position - 0.025) },
                    onPlayPause: {
                        playActions += 1
                        if isLoading { isLoading = false; isPlaying = false }
                        else { isPlaying.toggle() }
                    },
                    onForward: { forwardActions += 1; position = min(1, position + 0.05) },
                    onSleepTimer: { _ in sleepActions += 1 }, onShare: { shareActions += 1 },
                    onQueue: { queueOpens += 1; showingQueue = true },
                    onGoToArticle: {}, onCopyLink: {},
                    artworkImage: Self.covers[artworkVariant].map { Image(uiImage: $0) },
                    route: Button { routeActions += 1 } label: { Image(systemName: "airplay.audio").foregroundStyle(foreground) }
                    )
                }
                .frame(width: host.size.width, height: host.size.height)
                .onGeometryChange(for: CGRect.self, of: { _ in host.frame(in: .global) }) { frames["sheet"] = $0 }
            }
            .environment(\.fullPlayerGeometryProbe, { key, frame in frames[key] = frame })
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("full.player.fixture.report")
            .accessibilityValue(report)
            .sheet(isPresented: $showingQueue) {
                PodcastQueueSheet(episodes: episodes, currentEpisodeID: episodes[selectedIndex].id) { episode in
                    if let index = episodes.firstIndex(where: { $0.id == episode.id }) { selectedIndex = index }
                    queueSelections += 1
                    position = 0.1
                    showingQueue = false
                }
                .background(alignment: .topLeading) {
                    LocalQueueNativeDiagnostic()
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
    }
}

/// An on-demand native snapshot of this fixture's actual queue window. Reading
/// the AX value performs no action, scheduling, observation or SwiftUI mutation.
private struct LocalQueueNativeDiagnostic: UIViewRepresentable {
    func makeUIView(context: Context) -> LocalQueueNativeDiagnosticLabel {
        LocalQueueNativeDiagnosticLabel(frame: .zero)
    }
    func updateUIView(_ uiView: LocalQueueNativeDiagnosticLabel, context: Context) {}
}

private final class LocalQueueNativeDiagnosticLabel: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        textColor = .clear
        text = " "
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityIdentifier = "full.player.fixture.queue.native"
        accessibilityLabel = "Lokal kødiagnostik"
    }
    required init?(coder: NSCoder) { return nil }

    override var accessibilityValue: String? {
        get {
            guard let window else { return "{\"windowAttached\":false}" }
            let wantedID = "podcast.queue.list"
            var pending: [UIView] = [window]
            var visited: [UIView] = []
            var cursor = 0
            while cursor < pending.count && visited.count < 1_024 {
                let view = pending[cursor]
                cursor += 1
                visited.append(view)
                pending.append(contentsOf: view.subviews)
            }
            let matches = visited.filter { $0.accessibilityIdentifier == wantedID }
            let scrolls = Array(visited.compactMap { $0 as? UIScrollView }.prefix(32))
            let scrollReports = scrolls.map { scroll -> [String: Any] in
                let chain = ancestors(of: scroll)
                let directlyIdentified = scroll.accessibilityIdentifier == wantedID
                let matchingAncestor = chain.contains { $0.accessibilityIdentifier == wantedID }
                let matchingDescendant = matches.contains { $0.isDescendant(of: scroll) }
                let visible = visibleRect(of: scroll, in: window)
                let points: [(String, CGPoint)] = visible.isNull || visible.isEmpty ? [] : [
                    ("upperContent", CGPoint(x: visible.midX, y: visible.minY + visible.height * 0.25)),
                    ("midList", CGPoint(x: visible.midX, y: visible.midY)),
                    ("lowerContent", CGPoint(x: visible.midX, y: visible.minY + visible.height * 0.75)),
                    ("leftContent", CGPoint(x: visible.minX + visible.width * 0.15, y: visible.minY + visible.height * 0.4)),
                    ("rightContent", CGPoint(x: visible.minX + visible.width * 0.85, y: visible.minY + visible.height * 0.4))
                ]
                let hits: [[String: Any]] = points.map { name, point in
                    let hit = window.hitTest(point, with: nil)
                    return ["pointName": name, "point": vector(point),
                            "hitFound": hit != nil,
                            "ancestry": hit.map { ancestors(of: $0).map(viewDescription) } ?? []]
                }
                return [
                    "type": String(reflecting: type(of: scroll)),
                    "identifier": scroll.accessibilityIdentifier ?? "",
                    "directListID": directlyIdentified,
                    "ancestorListID": matchingAncestor,
                    "descendantListID": matchingDescendant,
                    "windowRect": rectangle(window.convert(scroll.bounds, from: scroll)),
                    "visibleWindowRect": rectangle(visible),
                    "bounds": rectangle(scroll.bounds),
                    "contentOffset": vector(scroll.contentOffset),
                    "contentSize": ["width": finite(scroll.contentSize.width), "height": finite(scroll.contentSize.height)],
                    "contentInset": insets(scroll.contentInset),
                    "adjustedContentInset": insets(scroll.adjustedContentInset),
                    "safeAreaInsets": insets(scroll.safeAreaInsets),
                    "isScrollEnabled": scroll.isScrollEnabled,
                    "isUserInteractionEnabled": scroll.isUserInteractionEnabled,
                    "isHidden": scroll.isHidden, "alpha": Double(scroll.alpha),
                    "isTracking": scroll.isTracking, "isDragging": scroll.isDragging,
                    "isDecelerating": scroll.isDecelerating,
                    "panState": scroll.panGestureRecognizer.state.rawValue,
                    "panEnabled": scroll.panGestureRecognizer.isEnabled,
                    "gestures": gestures(of: scroll),
                    "ancestry": chain.map(viewDescription),
                    "hitTests": hits
                ]
            }
            let value: [String: Any] = [
                "windowAttached": true,
                "windowBounds": rectangle(window.bounds),
                "windowFrame": rectangle(window.frame),
                "visitedViews": visited.count,
                "traversalTruncated": cursor < pending.count,
                "matchingListViews": matches.prefix(8).map(viewDescription),
                "scrollCount": scrolls.count,
                "scrolls": scrollReports
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
                return "{\"snapshotSerializationFailed\":true}"
            }
            return String(decoding: data, as: UTF8.self)
        }
        set { /* Native diagnostic value is always computed on demand. */ }
    }

    private func ancestors(of view: UIView) -> [UIView] {
        var result: [UIView] = []
        var current: UIView? = view
        while let value = current, result.count < 12 {
            result.append(value)
            current = value.superview
        }
        return result
    }
    private func viewDescription(_ view: UIView) -> [String: Any] {
        ["type": String(reflecting: type(of: view)),
         "identifier": view.accessibilityIdentifier ?? "",
         "isUserInteractionEnabled": view.isUserInteractionEnabled,
         "isHidden": view.isHidden, "alpha": Double(view.alpha),
         "gestures": gestures(of: view)]
    }
    private func gestures(of view: UIView) -> [[String: Any]] {
        (view.gestureRecognizers ?? []).prefix(12).map {
            ["type": String(reflecting: type(of: $0)), "state": $0.state.rawValue,
             "isEnabled": $0.isEnabled, "cancelsTouchesInView": $0.cancelsTouchesInView,
             "delaysTouchesBegan": $0.delaysTouchesBegan, "delaysTouchesEnded": $0.delaysTouchesEnded]
        }
    }
    private func visibleRect(of view: UIView, in window: UIWindow) -> CGRect {
        var result = window.convert(view.bounds, from: view).intersection(window.bounds)
        for ancestor in ancestors(of: view) {
            if ancestor.isHidden || ancestor.alpha <= 0.01 { return .null }
            if ancestor.clipsToBounds { result = result.intersection(window.convert(ancestor.bounds, from: ancestor)) }
        }
        return result
    }
    private func finite(_ value: CGFloat) -> Double { value.isFinite ? Double(value) : 0 }
    private func vector(_ point: CGPoint) -> [String: Double] { ["x": finite(point.x), "y": finite(point.y)] }
    private func rectangle(_ value: CGRect) -> [String: Any] {
        ["x": finite(value.minX), "y": finite(value.minY),
         "width": finite(value.width), "height": finite(value.height), "isNull": value.isNull]
    }
    private func insets(_ value: UIEdgeInsets) -> [String: Double] {
        ["top": finite(value.top), "left": finite(value.left),
         "bottom": finite(value.bottom), "right": finite(value.right)]
    }
}

/// Only the shipped timeline/play controls are mounted. Local buttons supply
/// loading/results; they do not stand in for AVPlayer, decoding or transport.
private struct LocalPlayerTimelineSmokeView: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var isLoading = true
    @State private var isPlaying = false
    @State private var position = 0.35
    @State private var reduceMotionOverride = false
    @State private var inactiveOverride = false
    @State private var phase = "loading"
    @State private var starts = 1
    @State private var editingBegins = 0
    @State private var seekCommits = 0
    @State private var playActions = 0
    @State private var frames: [String: CGRect] = [:]

    private var foreground: Color { colorScheme == .dark ? .white : .primary }
    private var report: String {
        let geometry = frames.mapValues { frame in
            ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
        }
        let value: [String: Any] = [
            "isLoading": isLoading, "isPlaying": isPlaying, "position": position,
            "phase": phase, "starts": starts, "editingBegins": editingBegins,
            "seekCommits": seekCommits, "playActions": playActions,
            "reduceMotionOverride": reduceMotionOverride,
            "systemReduceMotion": systemReduceMotion,
            "systemScenePhase": String(describing: scenePhase),
            "inactiveOverride": inactiveOverride,
            "dynamicType": String(describing: dynamicTypeSize), "frames": geometry
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase er startet")
                    .font(.caption).accessibilityIdentifier("timeline.fixture.firebase")
                Text("Lokal tidslinjeprøve").font(.headline)
                Text("Ingen lyd, netværk eller afspiller startes.")
                    .font(.footnote).foregroundStyle(.secondary)

                VStack(spacing: 20) {
                    PodcastPlayerTimeline(
                        value: $position, isLoading: isLoading, tint: foreground.opacity(0.95),
                        onEditingChanged: { editing in
                            if editing { editingBegins += 1 } else { seekCommits += 1 }
                        },
                        reduceMotionOverride: reduceMotionOverride ? true : nil,
                        scenePhaseOverride: inactiveOverride ? .inactive : nil
                    )
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frames["timeline"] = $0 }

                    PodcastPlayerPlayControl(isLoading: isLoading, isPlaying: isPlaying, tint: foreground) {
                        playActions += 1
                        if isLoading {
                            isLoading = false
                            isPlaying = false
                            phase = "paused"
                        } else {
                            isPlaying.toggle()
                        }
                    }
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frames["play"] = $0 }
                }
                // The actual controls inherit the system text size. Only the
                // fixture's explanatory controls below use a compact size.
                .dynamicTypeSize(dynamicTypeSize)

                Text(phase == "failed" ? "Lokal fejl — start igen" : "Lokal status: \(phase)")
                    .accessibilityIdentifier("timeline.fixture.phase")
                HStack(spacing: 12) {
                    Button("Start") {
                        isLoading = true; isPlaying = false; phase = "loading"; starts += 1
                    }.accessibilityIdentifier("timeline.fixture.start")
                    Button("Klar") {
                        isLoading = false; isPlaying = false; phase = "ready"
                    }.accessibilityIdentifier("timeline.fixture.ready")
                    Button("Fejl") {
                        isLoading = false; isPlaying = false; phase = "failed"
                    }.accessibilityIdentifier("timeline.fixture.fail")
                }
                .buttonStyle(.bordered)
                Toggle("Reduceret bevægelse (lokal)", isOn: $reduceMotionOverride)
                    .accessibilityIdentifier("timeline.fixture.reduced")
                Toggle("Inaktiv scene (lokal)", isOn: $inactiveOverride)
                    .accessibilityIdentifier("timeline.fixture.inactive")
                Text("Lokal tilstand")
                    .font(.caption2).foregroundStyle(.secondary)
                    .accessibilityIdentifier("timeline.fixture.report")
                    .accessibilityValue(report)
                Spacer(minLength: 0)
            }
            .dynamicTypeSize(.large)
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(uiColor: .systemBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

@MainActor
private struct LocalPodcastProgressContent: View {
    @ObservedObject var fixture: LocalPodcastProgressFixture
    @ObservedObject var store: PodcastPlaybackProgressStore
    @State private var showingQueue = false
    @State private var selectedQueueEpisodeID: String?

    // Fixed editorial examples use neither remote artwork nor playable audio.
    private let queueEpisodes: [PodcastEpisode] = [
        ("queue-one", "Hvem får plads i byen, når kulturen bliver presset ud?"),
        ("queue-two", "Et nyt blik på dansk musik og de historier, vi deler med hinanden"),
        ("queue-three", "Kulturens lange samtale: Mød menneskene, der giver os nye perspektiver")
    ].map { id, title in
        PodcastEpisode(
            id: id, articleId: nil, articleSlug: nil, title: title,
            subtitle: "Apropos Magazine · Redaktionel samtale", audioURL: nil,
            productionSourceURL: nil, duration: nil, artworkURL: nil,
            hosts: [], publishedDate: nil
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Kun lokale testdata") {
                    Text("Ingen lyd afspilles. Konto, lytteposition og gemmefejl simuleres kun i hukommelsen.")
                        .font(.footnote).fixedSize(horizontal: false, vertical: true)
                    Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase er startet")
                        .accessibilityIdentifier("progress.fixture.firebase")
                    Text("Aktiv læser: \(fixture.owner)")
                        .accessibilityIdentifier("progress.fixture.owner")
                    if let selectedQueueEpisodeID {
                        Text("Valgt episode: \(selectedQueueEpisodeID)")
                            .accessibilityIdentifier("progress.fixture.queueSelection")
                    }
                    ForEach(["Uafklaret", "Gæst", "Konto A", "Konto B"], id: \.self) { owner in
                        Button(owner) { fixture.select(owner) }
                            .tint(.primary).foregroundStyle(.primary)
                            .accessibilityIdentifier("progress.owner.\(owner)")
                    }
                }
                Section("Lytteposition") {
                    Text(store.snapshot.position(for: "local-episode").map { "Gemt position: \(Int($0)) sekunder" } ?? "Ingen gemt position")
                        .accessibilityIdentifier("progress.fixture.position")
                    Text(store.snapshot.playButtonTitle(for: "local-episode"))
                        .accessibilityIdentifier("progress.fixture.playTitle")
                    Text(store.snapshot.state == .ready ? "Lagring bekræftet i hukommelsen" : "Lagring ikke bekræftet")
                        .accessibilityIdentifier("progress.fixture.storageStatus")
                    Button("Gem 42 sekunder") { fixture.save() }
                        .tint(.primary).foregroundStyle(.primary)
                        .accessibilityIdentifier("progress.fixture.save")
                    Button("Aflevér gammelt svar fra A") { fixture.releaseOldSave() }
                        .tint(.primary).foregroundStyle(.primary)
                        .accessibilityIdentifier("progress.fixture.oldSave")
                    Toggle("Simulér gemmefejl", isOn: $fixture.failWrites)
                        .accessibilityIdentifier("progress.fixture.failWrites")
                        .onChange(of: fixture.failWrites) { _, _ in fixture.syncFailureFlag() }
                }
                Section { PodcastProgressNotice(store: store) }
            }
            .accessibilityIdentifier("progress.fixture.form")
            .navigationTitle("Lokal lytteposition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kø") { showingQueue = true }
                        .accessibilityIdentifier("progress.fixture.openQueue")
                }
            }
            .sheet(isPresented: $showingQueue) {
                PodcastQueueSheet(
                    episodes: queueEpisodes,
                    currentEpisodeID: "queue-three",
                    onTapEpisode: { episode in
                        selectedQueueEpisodeID = episode.id
                        showingQueue = false
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}
/// Local callbacks exercise the shipped mini-player surface and its gestures.
/// No playable URL, platform player, auth, persisted storage or remote image.
private struct LocalMiniPlayerMotionSmokeView: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var reduced = false
    @State private var visible = true
    @State private var playing = false
    @State private var opened = false
    @State private var opens = 0
    @State private var forwards = 0
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase er startet")
                    .font(.caption).accessibilityIdentifier("mini.fixture.firebase")
                Text(systemReduceMotion ? "Systembevægelse: reduceret" : "Systembevægelse: normal")
                    .font(.caption).accessibilityIdentifier("mini.fixture.systemMotion")
                Toggle("Reducer bevægelse", isOn: $reduced).accessibilityIdentifier("mini.fixture.reduced")
                Text("En fortælling at tage med").font(.title2.bold())
                Text("Den samme afspiller med lokale handlinger.").foregroundStyle(.secondary)
                ZStack(alignment: .top) {
                    if visible {
                        PodcastMiniPlayerContent(
                            title: "Kulturens lange samtale", subtitle: "Apropos Magazine",
                            artworkURL: nil, isAINarration: false, isBuffering: false,
                            isPlaying: playing, progress: 0.35,
                            togglePlayPause: { playing.toggle() }, seekForward: { forwards += 1 },
                            openPlayer: { opens += 1; opened = true }, closePlayer: { visible = false },
                            reduceMotionOverride: reduced ? true : nil
                        )
                        .dynamicTypeSize(dynamicTypeSize)
                        .transition(AppMotion.playerTransition(reduceMotion: reduced || systemReduceMotion))
                    }
                }
                .frame(height: 230, alignment: .top)
                .animation(AppMotion.playerSpring(response: 0.48, damping: 0.84, reduceMotion: reduced || systemReduceMotion), value: visible)
                Text(visible ? "Afspiller synlig" : "Afspiller lukket").accessibilityIdentifier("mini.fixture.visible")
                Text("Spol frem: \(forwards)").accessibilityIdentifier("mini.fixture.forwardCount")
                Text("Åbninger: \(opens)").accessibilityIdentifier("mini.fixture.openCount")
                Button("Vis afspiller") { visible = true }.accessibilityIdentifier("mini.fixture.restore")
                Spacer()
            }
            .padding(24)
            .dynamicTypeSize(.large) // Fixture controls stay compact; shipped surface uses the actual system size above.
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $opened) {
            VStack {
                Text("Afspiller åbnet").accessibilityIdentifier("mini.fixture.opened")
                Button("Luk") { opened = false }.accessibilityIdentifier("mini.fixture.closeSheet")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
            .presentationDetents([.medium])
        }
    }
}
#endif
