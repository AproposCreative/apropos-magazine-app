import SwiftUI
import SDWebImageSwiftUI

/// Header-only paging leaves each List's native row gestures alone. Both pages
/// keep their identity; visibility is explicit rather than inferred from mounting.
struct MinSidePages<FavoritesContent: View>: View {
    @ObservedObject var model: NotificationInboxModel
    let coverDisplayURL: (URL) -> URL?
    let onSettings: () -> Void
    private let favorites: FavoritesContent
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    #if DEBUG && targetEnvironment(simulator)
    @Environment(\.minSideReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.minSidePagingProbe) private var pagingProbe
    @State private var admissionClearReason = 0
    @State private var admissionClearCount = 0
    #endif
    private var reduceMotion: Bool {
        #if DEBUG && targetEnvironment(simulator)
        systemReduceMotion || reduceMotionOverride
        #else
        systemReduceMotion
        #endif
    }
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .largeTitle) private var titleHeight = 46
    @State private var page = 0
    @State private var viewportWidth: CGFloat = 0
    @State private var titleWidths: [CGFloat] = [0, 0]
    @State private var dragAdmission: HeaderDragAdmission?
    @State private var selectionRevision: UInt64 = 0
    @GestureState(resetTransaction: Transaction(animation: .easeOut(duration: 0.24)))
    private var drag = HeaderDrag()

    private struct HeaderDrag {
        var translation: CGFloat = 0
        var width: CGFloat = 0
        var horizontal: Bool?
    }
    private struct HeaderDragAdmission: Equatable {
        let width: CGFloat
        let horizontal: Bool
    }
    private var translation: CGFloat {
        guard scenePhase == .active, drag.horizontal == true,
              abs(drag.width - viewportWidth) < 0.5 else { return 0 }
        return drag.translation
    }
    private var progress: CGFloat {
        min(1, max(0, CGFloat(page) - translation / max(1, viewportWidth)))
    }

    init(model: NotificationInboxModel, coverDisplayURL: @escaping (URL) -> URL? = { $0 },
         onSettings: @escaping () -> Void, @ViewBuilder favorites: () -> FavoritesContent) {
        self.model = model
        self.coverDisplayURL = coverDisplayURL
        self.onSettings = onSettings
        self.favorites = favorites()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Group {
                    if dynamicType.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            title(0)
                            title(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        GeometryReader { geometry in
                            let width = geometry.size.width
                            let total = titleWidths[0] + 24 + titleWidths[1]
                            // Even in a narrow window, retain a tappable piece
                            // of the previous title as the visible way back.
                            let travel = min(max(0, total - width), max(0, titleWidths[0] - 44))
                            let offset = -travel * progress
                            HStack(spacing: 24) { title(0); title(1) }
                                .fixedSize(horizontal: true, vertical: false)
                                .offset(x: offset)
                                .frame(width: width, height: geometry.size.height, alignment: .leading)
                                .mask {
                                    HStack(spacing: 0) {
                                        LinearGradient(colors: [offset < -0.5 ? .clear : .black, .black], startPoint: .leading, endPoint: .trailing)
                                            .frame(width: 16)
                                        Color.black
                                        LinearGradient(colors: [.black, total + offset > width + 0.5 ? .clear : .black], startPoint: .leading, endPoint: .trailing)
                                            .frame(width: 22)
                                    }
                                }
                                .clipped()
                        }
                        .frame(height: titleHeight)
                    }
                }
                .contentShape(Rectangle())
                .highPriorityGesture(headerDrag)
                .notificationInboxMeasured("minside.header")

                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 46, height: 46)
                        .background(Color.gray.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Indstillinger")
                .accessibilityIdentifier("minside.settings")
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)

            GeometryReader { geometry in
                HStack(spacing: 0) {
                    favorites
                        .environment(\.minSidePageIsVisible, page == 0)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .allowsHitTesting(page == 0 && translation == 0)
                        .accessibilityHidden(page != 0)
                        .notificationInboxMeasured("minside.savedPage")
                    NotificationInboxView(model: model, coverDisplayURL: coverDisplayURL)
                        .environment(\.minSidePageIsVisible, page == 1)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .allowsHitTesting(page == 1 && translation == 0)
                        .accessibilityHidden(page != 1)
                        .notificationInboxMeasured("minside.messagesPage")
                }
                .frame(width: geometry.size.width * 2, height: geometry.size.height, alignment: .leading)
                .offset(x: -geometry.size.width * progress)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width / 2 }) {
                    guard abs(viewportWidth - $0) > 0.5 else { return }
                    viewportWidth = $0
                    dragAdmission = nil
                    selectionRevision &+= 1
                    #if DEBUG && targetEnvironment(simulator)
                    admissionClearReason = 1; admissionClearCount += 1
                    #endif
                }
            }
            .clipped()
            .notificationInboxMeasured("minside.viewport")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                dragAdmission = nil
                selectionRevision &+= 1
                #if DEBUG && targetEnvironment(simulator)
                admissionClearReason = 2; admissionClearCount += 1
                #endif
            }
        }
        .onDisappear { selectionRevision &+= 1; dragAdmission = nil }
        .modifier(MinSidePagingObservation(page: page, translation: translation, progress: progress,
            width: viewportWidth, reduceMotion: reduceMotion))
    }

    private func title(_ index: Int) -> some View {
        let label = index == 0 ? "Min side" : "Meddelelser"
        return Button { select(index) } label: {
            Text(LocalizedStringKey(label)).font(.largeTitle.bold())
                .foregroundStyle(page == index ? Color.primary : Color.secondary)
                .fixedSize(horizontal: !dynamicType.isAccessibilitySize, vertical: true)
                .frame(minWidth: 44, minHeight: 46, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(label)))
        .accessibilityValue(Text(LocalizedStringKey(page == index ? "Valgt" : "Ikke valgt")))
        .accessibilityAddTraits(page == index ? [.isHeader, .isSelected] : [.isHeader])
        .accessibilityIdentifier(index == 0 ? "minside.page.saved" : "minside.page.messages")
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { titleWidths[index] = $0 }
        .notificationInboxMeasured(index == 0 ? "minside.savedTitle" : "minside.messagesTitle")
    }
    private func select(_ index: Int) {
        #if DEBUG && targetEnvironment(simulator)
        var trace = MinSidePagingSample(selectedPage: page, dragTranslation: Double(translation),
            progress: Double(progress), viewportWidth: Double(viewportWidth), reduceMotion: reduceMotion)
        trace.dragEnd = ["selection": Double(index), "before": Double(page)]
        #endif
        dragAdmission = nil
        selectionRevision &+= 1
        #if DEBUG && targetEnvironment(simulator)
        admissionClearReason = 3; admissionClearCount += 1
        #endif
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { page = index }
        #if DEBUG && targetEnvironment(simulator)
        trace.dragEnd["after"] = Double(page)
        pagingProbe?(trace)
        #endif
    }
    private var headerDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($drag) { value, state, transaction in
                transaction.animation = nil
                if state.horizontal == nil {
                    state.horizontal = abs(value.translation.width) > abs(value.translation.height)
                    state.width = viewportWidth
                }
                if state.horizontal == true { state.translation = value.translation.width }
            }
            .onChanged { value in
                // GestureState may reset before onEnded. Retain only this
                // gesture's admission, not its visual translation or a timer.
                let admission = HeaderDragAdmission(width: drag.width > 0 ? drag.width : viewportWidth,
                    horizontal: drag.horizontal ?? (abs(value.translation.width) > abs(value.translation.height)))
                if dragAdmission == nil { selectionRevision &+= 1 }
                if admission != dragAdmission { dragAdmission = admission }
            }
            .onEnded { value in
                let admission = dragAdmission
                #if DEBUG && targetEnvironment(simulator)
                var sample = MinSidePagingSample(selectedPage: page, dragTranslation: Double(value.translation.width),
                    progress: Double(progress), viewportWidth: Double(viewportWidth), reduceMotion: reduceMotion)
                sample.dragEnd = ["admittedWidth": Double(admission?.width ?? -1),
                    "horizontal": admission?.horizontal == true ? 1 : 0,
                    "sceneActive": scenePhase == .active ? 1 : 0,
                    "predictedTranslation": Double(value.predictedEndTranslation.width),
                    "clearReason": Double(admissionClearReason), "clearCount": Double(admissionClearCount)]
                pagingProbe?(sample)
                #endif
                defer { dragAdmission = nil }
                guard admission?.horizontal == true,
                      abs((admission?.width ?? 0) - viewportWidth) < 0.5,
                      scenePhase == .active else { return }
                let projected = CGFloat(page) - value.predictedEndTranslation.width / max(1, viewportWidth)
                let destination = projected >= 0.5 ? 1 : 0
                let revision = selectionRevision, startPage = page, width = viewportWidth
                // Commit once after the gesture-reset transaction. A newer
                // touch, selection, layout or lifecycle event cancels it.
                DispatchQueue.main.async {
                    guard selectionRevision == revision, page == startPage,
                          abs(viewportWidth - width) < 0.5 else { return }
                    select(destination)
                }
            }
    }
}

private struct MinSidePageVisibilityKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var minSidePageIsVisible: Bool {
        get { self[MinSidePageVisibilityKey.self] }
        set { self[MinSidePageVisibilityKey.self] = newValue }
    }
}

private struct MinSidePagingObservation: ViewModifier {
    let page: Int
    let translation: CGFloat
    let progress: CGFloat
    let width: CGFloat
    let reduceMotion: Bool
    #if DEBUG && targetEnvironment(simulator)
    @Environment(\.minSidePagingProbe) private var probe
    #endif
    @ViewBuilder func body(content: Content) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        let sample = MinSidePagingSample(selectedPage: page, dragTranslation: Double(translation),
            progress: Double(progress), viewportWidth: Double(width), reduceMotion: reduceMotion)
        content.onChange(of: sample, initial: true) { _, value in probe?(value) }
        #else
        content
        #endif
    }
}

/// Inline content, with the enclosing Min side header and navigation kept intact.
struct NotificationInboxView: View {
    @Environment(\.locale) private var interfaceLocale
    @ObservedObject var model: NotificationInboxModel
    var coverDisplayURL: (URL) -> URL? = { $0 }
    @State private var navigationUnavailable = false
    @Environment(\.minSidePageIsVisible) private var pageIsVisible

    private var visibleItems: [NotificationInboxItem] {
        model.visibleItems(language: AppLocalization.language(for: interfaceLocale))
    }

    var body: some View {
        List {
            if let issue = model.issue {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringKey(issue)).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        Button("Prøv igen") { model.refresh() }.frame(minHeight: 44)
                    }.accessibilityIdentifier("notifications.issue")
                }.listRowSeparator(.hidden)
            }
            if visibleItems.isEmpty {
                Section {
                    if model.refreshing {
                        ProgressView("Henter meddelelser")
                            .frame(maxWidth: .infinity, minHeight: 120)
                            .accessibilityIdentifier("notifications.loading")
                    } else {
                        ContentUnavailableView("Ingen meddelelser", systemImage: "bell",
                            description: Text("Nye beskeder vises her, når de modtages på denne enhed."))
                            .accessibilityIdentifier("notifications.empty")
                    }
                }.listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(visibleItems) { item in
                        Group {
                            if item.target != nil {
                                Button {
                                    // The existing typed route retains its own readiness,
                                    // lookup and playback authority. No second resolver.
                                    navigationUnavailable = !model.open(item.id)
                                } label: { NotificationInboxRow(item: item, coverDisplayURL: coverDisplayURL) }
                                .buttonStyle(NotificationInboxTapStyle())
                                .accessibilityLabel(accessibleText(item))
                                .accessibilityIdentifier("notifications.item.\(item.id)")
                            } else {
                                NotificationInboxRow(item: item, coverDisplayURL: coverDisplayURL)
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel(accessibleText(item))
                                    .accessibilityIdentifier("notifications.message.\(item.id)")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Slet", systemImage: "trash", role: .destructive) {
                                model.delete(item.id)
                            }
                            .accessibilityIdentifier("notifications.delete.\(item.id)")
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("notifications.list")
        .refreshable { model.refresh() }
        .onAppear { if pageIsVisible { model.refresh() } }
        .onChange(of: pageIsVisible) { _, visible in if visible { model.refresh() } }
        .alert("Indholdet kan ikke åbnes lige nu", isPresented: $navigationUnavailable) {
            Button("OK", role: .cancel) {}
        } message: { Text("Prøv igen, når appen er klar.") }
    }
    private func accessibleText(_ item: NotificationInboxItem) -> String {
        "\(item.title). \(item.body). \(item.date.formatted(.dateTime.day().month().year().locale(interfaceLocale)))"
    }
}

/// A moved touch inside a wide message row is not an activation. A tap
/// recognizer can fail without consuming the List's vertical scroll gesture.
private struct NotificationInboxTapStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .onTapGesture { configuration.trigger() }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { configuration.trigger() }
            .focusable()
            .onKeyPress(.return) { configuration.trigger(); return .handled }
            .onKeyPress(.space) { configuration.trigger(); return .handled }
    }
}

private struct NotificationInboxRow: View {
    let item: NotificationInboxItem
    let coverDisplayURL: (URL) -> URL?
    #if DEBUG && targetEnvironment(simulator)
    @Environment(\.notificationInboxArtworkProbe) private var artworkProbe
    #endif
    var body: some View {
        Group {
            if let remote = item.articleImageURL, let display = coverDisplayURL(remote) {
                // Keep the existing loader/cache. Missing or failed artwork uses
                // the same text body without reserving a blank thumbnail slot.
                WebImage(url: display, options: [.scaleDownLargeImages], isAnimating: .constant(false)) { phase in
                    row(image: phase.image)
                }
                .onSuccess { _, _, _ in reportArtwork(remote, phase: "loaded") }
                .onFailure { _ in reportArtwork(remote, phase: "failed") }
                .id(display)
            } else {
                row(image: nil)
            }
        }
    }
    private func reportArtwork(_ url: URL, phase: String) {
        #if DEBUG && targetEnvironment(simulator)
        artworkProbe?("\(item.id).\(url.absoluteString)", phase)
        #endif
    }
    private func row(image: Image?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).font(.headline).lineLimit(item.target == nil ? nil : 2)
                Text(item.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(item.target == nil ? nil : 3)
                    .notificationInboxMeasured("body.\(item.id)")
                Text(item.date, format: .dateTime.day().month())
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .notificationInboxMeasured("text.\(item.id)")
            if let image {
                image.resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 72)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .notificationInboxMeasured("cover.\(item.id).\(item.articleImageURL?.absoluteString ?? "")")
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 8).frame(minHeight: 44, alignment: .top)
        .contentShape(Rectangle())
        .notificationInboxMeasured("row.\(item.id)")
    }
}

#if DEBUG && targetEnvironment(simulator)
struct MinSidePagingSample: Equatable {
    let selectedPage: Int
    let dragTranslation: Double
    let progress: Double
    let viewportWidth: Double
    let reduceMotion: Bool
    var dragEnd: [String: Double] = [:]
}
private struct MinSidePagingProbeKey: EnvironmentKey {
    static let defaultValue: ((MinSidePagingSample) -> Void)? = nil
}
private struct MinSideReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue = false
}
private struct NotificationInboxGeometryProbeKey: EnvironmentKey {
    static let defaultValue: ((String, CGRect) -> Void)? = nil
}
private struct NotificationInboxArtworkProbeKey: EnvironmentKey {
    static let defaultValue: ((String, String) -> Void)? = nil
}
extension EnvironmentValues {
    var minSideReduceMotionOverride: Bool {
        get { self[MinSideReduceMotionOverrideKey.self] }
        set { self[MinSideReduceMotionOverrideKey.self] = newValue }
    }
    var minSidePagingProbe: ((MinSidePagingSample) -> Void)? {
        get { self[MinSidePagingProbeKey.self] }
        set { self[MinSidePagingProbeKey.self] = newValue }
    }
    var notificationInboxGeometryProbe: ((String, CGRect) -> Void)? {
        get { self[NotificationInboxGeometryProbeKey.self] }
        set { self[NotificationInboxGeometryProbeKey.self] = newValue }
    }
    var notificationInboxArtworkProbe: ((String, String) -> Void)? {
        get { self[NotificationInboxArtworkProbeKey.self] }
        set { self[NotificationInboxArtworkProbeKey.self] = newValue }
    }
}
#endif
private struct NotificationInboxFrameProbe: ViewModifier {
    let key: String
    #if DEBUG && targetEnvironment(simulator)
    @Environment(\.notificationInboxGeometryProbe) private var probe
    #endif
    @ViewBuilder func body(content: Content) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        content.onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { probe?(key, $0) }
        #else
        content
        #endif
    }
}
private extension View {
    func notificationInboxMeasured(_ key: String) -> some View {
        modifier(NotificationInboxFrameProbe(key: key))
    }
}
