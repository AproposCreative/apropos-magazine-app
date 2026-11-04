import CryptoKit
import FirebaseCore
import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import Apropos

/// Reproducible local before/after inputs. Timing is evidence, not a flaky
/// pass/fail budget or a claim about iPhone frame rate, downloads or first paint.
@MainActor
final class ArticleHTMLPreparationPerformanceTests: XCTestCase {
    private struct Input {
        let name: String
        let html: String
        let imageBytes: Int
        let cache: OfflineArticleImageCache
        let root: URL
        var digest: String { SHA256.hash(data: Data(html.utf8)).map { String(format: "%02x", $0) }.joined() }
    }
    private func input(paragraphs: Int, imageCount: Int) throws -> Input {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("article-preparation-measure-" + UUID().uuidString)
        let key = String(repeating: "a", count: 64), directory = root.appendingPathComponent(key)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let tinyPNG = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        // Valid PNG with deterministic trailing bytes: no remote request and no
        // expensive fixture generation inside the measured interval.
        let bytes = tinyPNG + Data(repeating: 0, count: 1024 * 1024 - tinyPNG.count)
        var mapping: [String: String] = [:]
        let images = try (0..<imageCount).map { index -> String in
            let remote = "https://images.example.invalid/editorial-\(index).png"
            let filename = String(repeating: String(index + 1), count: 64) + ".png"
            mapping[remote] = filename
            try bytes.write(to: directory.appendingPathComponent(filename), options: .atomic)
            return "<img src='\(remote)'/><p>Foto: Apropos \(index)</p>"
        }.joined()
        try JSONEncoder().encode(mapping).write(to: directory.appendingPathComponent("mapping.json"), options: .atomic)
        let prose = (0..<paragraphs).map { index in
            "<p>Afsnit \(index). En artikel giver plads til nysgerrighed, musik og kultur. Vi undersøger detaljerne og lader læseren følge fortællingen i sit eget tempo. Æ, ø og å skal bevares præcist.</p>"
        }.joined()
        let cache = OfflineArticleImageCache(cacheDirectory: root, download: { _ in
            XCTFail("Measurement must not download images"); throw URLError(.unsupportedURL)
        }, online: { false }, preparationAccess: { id, revision in
            .init(contentKey: id == "fixture" && revision == "r1" ? key : nil,
                  generation: nil, isCurrent: { true })
        })
        return Input(name: "paragraphs-\(paragraphs)-images-\(imageCount)", html: "<style>p{color:red}</style>" + images + prose,
                     imageBytes: imageCount * bytes.count, cache: cache, root: root)
    }
    private func milliseconds(since time: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - time) / 1_000_000
    }
    private func record(_ name: String, input: Input, values: [[String: Double]]) throws {
        let object: [String: Any] = ["measurement": name, "input": input.name, "htmlSHA256": input.digest,
            "htmlBytes": input.html.utf8.count, "sourceImageBytes": input.imageBytes,
            "scope": "Hermetic simulator; local preparation and measured-document readiness, not first paint or device FPS",
            "samples": values]
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: bytes, uniformTypeIdentifier: "public.json")
        attachment.name = "article-preparation-\(name)-\(input.name)"; attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMeasureCurrentPreparationWithFixedHTMLAndLocalImageBytes() async throws {
        XCTAssertNil(FirebaseApp.allApps)
        for (paragraphs, images) in [(30, 0), (300, 2)] {
            let input = try input(paragraphs: paragraphs, imageCount: images)
            defer { try? FileManager.default.removeItem(at: input.root) }
            var values: [[String: Double]] = []
            for _ in 0..<5 {
                let started = DispatchTime.now().uptimeNanoseconds
                let access = input.cache.capturePreparationAccess(articleID: "fixture", revision: "r1")
                let request = ArticleHTMLPreparation.Input(html: input.html,
                    targetImageWidth: ArticleHTMLProcessor.capturedImageWidth(), bodyFontSize: 18,
                    documentID: UUID().uuidString, contentKey: access.contentKey)
                let mainElapsed = milliseconds(since: started)
                let cache = input.cache
                let prepared = await Task.detached {
                    ArticleHTMLPreparation.prepare(request, cache: cache)
                }.value
                let result = try XCTUnwrap(prepared)
                let elapsed = milliseconds(since: started)
                XCTAssertTrue(access.isCurrent())
                XCTAssertTrue(result.html.contains("Afsnit 0"))
                XCTAssertFalse(result.html.contains("https://images.example.invalid"))
                values.append(["preparationWallMs": elapsed, "mainActorPreparationMs": mainElapsed,
                               "outputBytes": Double(result.html.utf8.count)])
            }
            try record("preparation", input: input, values: values)
        }
        XCTAssertNil(FirebaseApp.allApps)
    }

    func testMeasureActualRendererToMeasuredDocumentReadyAndMainQueueDelay() async throws {
        XCTAssertNil(FirebaseApp.allApps)
        for (paragraphs, images) in [(30, 0), (300, 2)] {
            let input = try input(paragraphs: paragraphs, imageCount: images)
            defer { try? FileManager.default.removeItem(at: input.root) }
            var values: [[String: Double]] = []
            for sample in 0..<3 {
                let ready = expectation(description: "Actual HTMLTextView measured document \(sample)")
                var readyMs: Double?
                let probe = MainQueueDelayProbe()
                let started = DispatchTime.now().uptimeNanoseconds
                let view = PreparationMeasurementView(html: input.html, cache: input.cache, ready: { overflow in
                    XCTAssertFalse(overflow)
                    guard readyMs == nil else { return }
                    readyMs = self.milliseconds(since: started); ready.fulfill()
                })
                let controller = UIHostingController(rootView: view)
                let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
                let window: UIWindow
                if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                    window = UIWindow(windowScene: scene); window.frame = frame
                } else { window = UIWindow(frame: frame) }
                probe.start()
                window.rootViewController = controller; window.isHidden = false
                controller.view.frame = frame; controller.view.layoutIfNeeded()
                await fulfillment(of: [ready], timeout: 12)
                // Drain already posted main-queue probes before stopping. This
                // is an event boundary, not a sleep chosen to hide a regression.
                await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
                probe.stop()
                values.append(["measuredDocumentReadyMs": try XCTUnwrap(readyMs),
                    "maxMainQueueDelayMs": probe.maximumDelayMs, "mainQueueSamples": Double(probe.sampleCount)])
                window.isHidden = true; window.rootViewController = nil
            }
            try record("renderer", input: input, values: values)
        }
        XCTAssertNil(FirebaseApp.allApps)
    }
}

@MainActor
private struct PreparationMeasurementView: View {
    let html: String
    let cache: OfflineArticleImageCache
    let ready: (Bool) -> Void
    @State private var height: CGFloat = 240
    @State private var motion = ArticleReadingMotionController()
    var body: some View {
        ScrollView {
            HTMLTextView(html: html, articleId: "fixture", articleRevision: "r1", dynamicHeight: $height,
                readingMotion: motion, onHorizontalOverflow: ready, offlineImageCache: cache)
                .frame(height: max(240, height))
        }.environment(\.dynamicTypeSize, .large)
    }
}

private final class MainQueueDelayProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var maximum = 0.0
    private var count = 0
    var maximumDelayMs: Double { lock.lock(); defer { lock.unlock() }; return maximum }
    var sampleCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    func start() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "article-preparation-measure"))
        timer.schedule(deadline: .now(), repeating: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            let posted = DispatchTime.now().uptimeNanoseconds
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let delay = Double(DispatchTime.now().uptimeNanoseconds - posted) / 1_000_000
                self.lock.lock(); self.maximum = max(self.maximum, delay); self.count += 1; self.lock.unlock()
            }
        }
        self.timer = timer; timer.resume()
    }
    func stop() { timer?.cancel(); timer = nil }
    deinit { timer?.cancel() }
}
