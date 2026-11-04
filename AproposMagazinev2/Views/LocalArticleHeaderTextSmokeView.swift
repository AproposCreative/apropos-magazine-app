#if DEBUG && targetEnvironment(simulator)
import FirebaseCore
import SwiftUI
import UIKit

/// Actual article typography and tag flow, with local layout observations only.
struct LocalArticleHeaderTextSmokeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var frames: [String: CGRect] = [:]
    private let scenario: String
    private let before: Bool
    private let keys = ["header", "title", "text.title", "subtitle", "text.subtitle", "tags"]

    init() {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-ArticleHeaderTextScenario"), args.indices.contains(index + 1) {
            scenario = args[index + 1]
        } else { scenario = "short" }
        before = args.contains("-ArticleHeaderTextBefore")
    }

    private var title: String {
        switch scenario {
        case "long": "Kulturen, der samler os og giver byen nye perspektiver"
        case "editorial": "Kulturen, der samler os"
        default: "Byliv"
        }
    }
    private var subtitle: String {
        scenario == "short" ? "Bag historien." : "Mød menneskerne, som giver byen nye perspektiver."
    }
    private var ready: Bool {
        keys.allSatisfy {
            guard let frame = frames[$0] else { return false }
            return frame.width > 0 && frame.height > 0 && !frame.isInfinite && !frame.isNull
        }
    }
    private var report: String {
        let payload: [String: Any] = [
            "scenario": scenario, "before": before, "title": title, "subtitle": subtitle,
            "environmentAccessibility": dynamicTypeSize.isAccessibilitySize,
            "systemAccessibility": UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory,
            "systemCategory": UIApplication.shared.preferredContentSizeCategory.rawValue,
            "frames": frames.mapValues { rect in
                ["x": Double(rect.minX), "y": Double(rect.minY), "width": Double(rect.width), "height": Double(rect.height)]
            }
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
                        .accessibilityIdentifier("headerText.firebase")
                    Text(ready ? "Klar" : "Måler layout").accessibilityIdentifier("headerText.ready")
                    Text(before ? "Førmåling · \(scenario)" : "Layoutkontrol · \(scenario)")
                    Text("Renderet geometri").accessibilityIdentifier("headerText.geometry").accessibilityValue(report)
                }
                .font(.caption).dynamicTypeSize(.large).padding(8)
                .frame(maxWidth: .infinity).background(.quaternary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ArticleHeaderTitle(text: title, textColor: .primary, onTextFrame: { record("text.title", $0) })
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { record("title", $0) }
                            .accessibilityIdentifier("headerText.title")
                        ArticleHeaderSubtitle(text: subtitle, textColor: .primary, onTextFrame: { record("text.subtitle", $0) })
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { record("subtitle", $0) }
                            .accessibilityIdentifier("headerText.subtitle")
                        ArticleTagFlowLayout(spacing: 8, lineSpacing: 8, alignment: .center) {
                            ArticleTagChip(text: "Kultur")
                            ArticleTagChip(text: "Perspektiver")
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { record("tags", $0) }
                        .padding(.horizontal, 16).padding(.top, 5)
                        .accessibilityIdentifier("headerText.tags")
                    }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { record("header", $0) }
                    .padding(.vertical, 24)
                }
                .accessibilityIdentifier("headerText.scroll")
            }
            .navigationTitle("Artikeloverskrift")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func record(_ key: String, _ frame: CGRect) {
        if frames[key] != frame { frames[key] = frame }
    }
}
#endif
