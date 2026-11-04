#if DEBUG && targetEnvironment(simulator)
import FirebaseCore
import SwiftUI
import UIKit

/// Uses the shipped chip and flow. Geometry probes observe layout, never propose a size.
struct LocalArticleTagsSmokeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var frames: [String: CGRect] = [:]
    @State private var authorTaps = 0
    @State private var showSavedStatus = true
    @StateObject private var offline = LocalOfflineBodyFixture(scenario: .savedTags)

    private struct Sample: Identifiable {
        let id: String
        let text: String
        var isAuthor = false
    }
    private let scenario: String
    private let before: Bool

    init() {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-ArticleTagsScenario"), args.indices.contains(index + 1) {
            scenario = args[index + 1]
        } else { scenario = "author" }
        before = args.contains("-ArticleTagsBefore")
    }

    private var isSavedScenario: Bool { scenario.hasPrefix("saved") }

    private var samples: [Sample] {
        switch scenario {
        case "savedOnly": return []
        case "savedMixed", "savedTransition":
            return [.init(id: "author", text: "Signe Jensen", isAuthor: true),
                    .init(id: "category.0", text: "Kultur")]
        case "savedLong":
            return [.init(id: "author", text: "Alexandra Mathilde Frederikke Søndergaard-Christiansen Holm", isAuthor: true),
                    .init(id: "category.0", text: "Musik")]
        case "topic":
            return [.init(id: "short", text: "Musik"),
                    .init(id: "long", text: "Litteratur, samfund og internationale kulturoplevelser for nysgerrige læsere")]
        case "word":
            return [.init(id: "short", text: "Musik"),
                    .init(id: "long", text: "Musikfestivalanmeldelseroginternationaleoplevelserogkulturfortællinger")]
        case "mixed":
            return [.init(id: "short", text: "Musik"),
                    .init(id: "author", text: "Signe Jensen", isAuthor: true),
                    .init(id: "topic", text: "Kultur")]
        default:
            return [.init(id: "short", text: "Musik"),
                    .init(id: "long", text: "Alexandra Mathilde Frederikke Søndergaard-Christiansen Holm", isAuthor: true)]
        }
    }

    private var geometryReady: Bool {
        (["container"] + samples.flatMap { ["chip." + $0.id, "text." + $0.id] }
            + (isSavedScenario && showSavedStatus ? ["status"] : [])).allSatisfy {
            guard let frame = frames[$0] else { return false }
            return frame.width > 0 && frame.height > 0 && !frame.isInfinite && !frame.isNull
        }
    }

    private var report: String {
        let values = frames.mapValues { rect in
            ["x": Double(rect.minX), "y": Double(rect.minY), "width": Double(rect.width), "height": Double(rect.height)]
        }
        let payload: [String: Any] = [
            "scenario": scenario, "before": before, "frames": values,
            "bodyState": offline.status.map { String(describing: $0) } ?? "unstarted",
            "prepareCalls": offline.prepareCalls, "probes": offline.probes,
            "fetches": offline.fetches, "writes": offline.writes,
            "redraws": offline.redraws, "authorTaps": authorTaps,
            "leaseID": offline.ticket?.leaseID.uuidString ?? "",
            "statusVisible": showSavedStatus,
            "labels": Dictionary(uniqueKeysWithValues: samples.map { ($0.id, $0.text.uppercased()) }),
            "environmentAccessibility": dynamicTypeSize.isAccessibilitySize,
            "systemAccessibility": UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory,
            "systemCategory": UIApplication.shared.preferredContentSizeCategory.rawValue
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let result = String(data: data, encoding: .utf8) else { return "{}" }
        return result
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text(FirebaseApp.allApps == nil ? "Firebase: ikke startet" : "FEJL: Firebase startet")
                        .accessibilityIdentifier("tags.firebase")
                    Text(geometryReady ? "Klar" : "Måler layout")
                        .accessibilityIdentifier("tags.ready")
                    Text("Forfattertryk: \(authorTaps)").accessibilityIdentifier("tags.authorTaps")
                    Text(before ? "Førmåling · \(scenario)" : "Layoutkontrol · \(scenario)")
                    Text("Renderet geometri").accessibilityIdentifier("tags.geometry").accessibilityValue(report)
                    if isSavedScenario {
                        HStack {
                            Button("Aflevér kontrol", action: offline.releaseProbe)
                                .accessibilityIdentifier("tags.releaseProbe").disabled(offline.heldProbeCount == 0)
                            Button("Gentegn", action: offline.redraw).accessibilityIdentifier("tags.redraw")
                        }
                        if scenario == "savedTransition" {
                            HStack {
                                Button("Fejl i hentning", action: offline.failSavedTagsReload)
                                    .accessibilityIdentifier("tags.failReload").disabled(offline.status != .available)
                                Button("Aflevér tekst", action: offline.release)
                                    .accessibilityIdentifier("tags.releaseBody").disabled(offline.heldCount == 0)
                            }
                        } else if scenario == "savedMixed" {
                            Button("Skjul statusslot (fixture)") { showSavedStatus = false }
                                .accessibilityIdentifier("tags.hideStatus")
                        }
                    }
                }
                .font(.caption).dynamicTypeSize(.large).padding(8)
                .frame(maxWidth: .infinity).background(.quaternary)

                ScrollView {
                    tagContent
                    .frame(maxWidth: .infinity, alignment: .center)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { record("container", $0) }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 24)
                }
                .accessibilityIdentifier("tags.scroll")
            }
            .navigationTitle("Artikelmærker")
            .navigationBarTitleDisplayMode(.inline)
            .task { if isSavedScenario { offline.start() } }
        }
    }

    @ViewBuilder private var tagContent: some View {
        if isSavedScenario {
            ArticleHeaderTagGroup(authorName: samples.first(where: \.isAuthor)?.text,
                categories: samples.filter { !$0.isAuthor }.map(\.text), openAuthor: { authorTaps += 1 }) {
                if showSavedStatus, let original = offline.ticket, let state = offline.status {
                    ArticleOfflineBodyStatusView(ticket: original, state: state,
                        prepare: { offline.prepare($0) }, retry: { offline.retry(original) })
                }
            }
            .measuringFrames { record($0, $1) }
            // Isolate layout/lifetime from the simulator launch activation hop.
            // Actual foreground revalidation remains a separate production behavior.
            .environment(\.scenePhase, .active)
        } else {
            ArticleTagFlowLayout(spacing: 8, lineSpacing: 8, alignment: .center) {
                ForEach(samples) { sample in
                    if sample.isAuthor {
                        Button { authorTaps += 1 } label: { chip(sample) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("tags.author")
                    } else { chip(sample) }
                }
            }
        }
    }

    private func chip(_ sample: Sample) -> some View {
        ArticleTagChip(text: sample.text, onTextFrame: { record("text." + sample.id, $0) })
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { record("chip." + sample.id, $0) }
            .accessibilityIdentifier("tags.chip." + sample.id)
    }

    private func record(_ key: String, _ frame: CGRect) {
        if frames[key] != frame { frames[key] = frame }
    }
}
#endif
