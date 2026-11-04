import XCTest
import CoreGraphics
import UIKit

/// Shipped controls with local state transitions. No AVPlayer, media decoding,
/// network, playback timing or physical background behaviour is exercised.
final class PlayerTimelineSmokeTests: XCTestCase {
    private var app: XCUIApplication!

    private struct Frame: Decodable {
        let x: Double, y: Double, width: Double, height: Double
        var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    }
    private struct Report: Decodable {
        let isLoading: Bool
        let isPlaying: Bool
        let position: Double
        let phase: String
        let starts: Int
        let editingBegins: Int
        let seekCommits: Int
        let playActions: Int
        let reduceMotionOverride: Bool
        let systemReduceMotion: Bool
        let inactiveOverride: Bool
        let frames: [String: Frame]
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        if name.contains("FullPlayerSheet") {
            app.launchArguments = ["-AproposSmokeTesting", "-AproposProgressSmoke", "-AproposFullPlayerSmoke"]
            if name.contains("Narrated") { app.launchArguments.append("-AproposFullPlayerNarratedSmoke") }
            if name.contains("Reduced") { app.launchArguments.append("-AproposFullPlayerReduceMotion") }
            if name.contains("ShortTitle") { app.launchArguments.append("-AproposFullPlayerShortTitleSmoke") }
            if name.contains("Traversal") { app.launchArguments.append("-AproposFullPlayerTitleTraversalSmoke") }
            app.launch()
            XCTAssertTrue(app.staticTexts["full.player.fixture.firebase"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["full.player.fixture.firebase"].label, "Firebase: ikke startet")
            return
        }
        app.launchArguments = ["-AproposSmokeTesting", "-AproposProgressSmoke", "-AproposPlayerTimelineSmoke"]
        app.launch()
        XCTAssertTrue(app.staticTexts["timeline.fixture.firebase"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["timeline.fixture.firebase"].label, "Firebase: ikke startet")
        _ = try waitForReport { $0.frames["timeline"] != nil && $0.frames["play"] != nil }
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    private var loading: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "podcast.timeline.loading").firstMatch
    }
    private var slider: XCUIElement { app.sliders["podcast.timeline.seek"] }
    private var play: XCUIElement { app.buttons["podcast.player.playPause"] }
    private var diagnostic: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "timeline.fixture.report").firstMatch
    }

    private func report() -> Report? {
        guard diagnostic.exists, let text = diagnostic.value as? String,
              let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Report.self, from: data)
    }

    @discardableResult
    private func waitForReport(file: StaticString = #filePath, line: UInt = #line,
                               _ predicate: (Report) -> Bool) throws -> Report {
        for _ in 0..<30 {
            if let value = report(), predicate(value) { return value }
            Thread.sleep(forTimeInterval: 0.1)
        }
        capture("Timeline — state did not settle")
        XCTFail("Expected local timeline state was not observed", file: file, line: line)
        return try XCTUnwrap(report(), file: file, line: line)
    }

    private func capture(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let state = XCTAttachment(string: diagnostic.value as? String ?? "missing actual state")
        state.name = "\(name) — actual state and geometry"
        state.lifetime = .keepAlways; add(state)
    }

    private func captureFrames(_ phase: String) {
        // Native screenshots retain multiple real presentation frames. The
        // xcresult video and these frames require independent motion review;
        // AX state alone is never reported as a left-to-right animation proof.
        for index in 0..<6 {
            if index > 0 { Thread.sleep(forTimeInterval: 0.24) }
            capture("Timeline — \(phase) frame \(index + 1)")
        }
    }

    private func assertLoading(file: StaticString = #filePath, line: UInt = #line) throws -> CGRect {
        XCTAssertTrue(loading.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(loading.label, "Lyden indlæses", file: file, line: line)
        XCTAssertEqual(loading.value as? String, "Indlæser", file: file, line: line)
        XCTAssertFalse(slider.exists, "Loading must expose no adjustable seek control", file: file, line: line)
        XCTAssertEqual(app.activityIndicators.count, 0, "No spinner may replace the play icon", file: file, line: line)
        XCTAssertEqual(play.label, "Pause indlæsning", file: file, line: line)
        XCTAssertTrue(play.isHittable, file: file, line: line)
        let state = try waitForReport(file: file, line: line) { $0.isLoading }
        let frame = try XCTUnwrap(state.frames["timeline"]?.rect, file: file, line: line)
        let playFrame = try XCTUnwrap(state.frames["play"]?.rect, file: file, line: line)
        XCTAssertEqual(frame.height, 44, accuracy: 0.5, file: file, line: line)
        XCTAssertTrue(app.frame.contains(frame), "The complete timeline must remain visible", file: file, line: line)
        XCTAssertTrue(app.frame.contains(playFrame), "The entire play control must remain visible", file: file, line: line)
        XCTAssertGreaterThanOrEqual(playFrame.width, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(playFrame.height, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(playFrame.minY, frame.maxY, file: file, line: line)
        return frame
    }

    private func toggle(_ id: String, to enabled: Bool) {
        let row = app.switches[id]
        XCTAssertTrue(row.exists)
        let control = row.switches.firstMatch.exists ? row.switches.firstMatch : row
        XCTAssertTrue(control.isHittable)
        if control.value as? String != (enabled ? "1" : "0") { control.tap() }
        XCTAssertEqual(control.value as? String, enabled ? "1" : "0")
    }

    func testLoadingTimelineReplacesSpinnerAndTransitionsToSeekingAndRetry() throws {
        let originalFrame = try assertLoading()
        let original = try XCTUnwrap(report())
        XCTAssertEqual(original.position, 0.35, accuracy: 0.001)
        XCTAssertFalse(original.reduceMotionOverride)
        XCTAssertFalse(original.inactiveOverride)
        captureFrames(original.systemReduceMotion ? "system reduced loading" : "animated loading")

        // A drag over the loading track must not manufacture a seek or progress.
        let start = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: originalFrame.minX + 8, dy: originalFrame.midY))
        let end = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: originalFrame.maxX - 8, dy: originalFrame.midY))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        let held = try XCTUnwrap(report())
        XCTAssertEqual(held.position, original.position, accuracy: 0.001)
        XCTAssertEqual(held.editingBegins, 0)
        XCTAssertEqual(held.seekCommits, 0)

        app.buttons["timeline.fixture.ready"].tap()
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        XCTAssertFalse(loading.exists)
        XCTAssertEqual(play.label, "Afspil")
        let ready = try waitForReport { !$0.isLoading && $0.phase == "ready" }
        XCTAssertEqual(try XCTUnwrap(ready.frames["timeline"]?.rect), originalFrame,
                       "Loading→ready must keep the same timeline footprint")
        slider.adjust(toNormalizedSliderPosition: 0.72)
        let sought = try waitForReport { $0.editingBegins > 0 && $0.seekCommits > 0 }
        XCTAssertGreaterThan(sought.position, 0.60)
        XCTAssertLessThan(sought.position, 0.85)
        play.tap()
        _ = try waitForReport { $0.playActions == 1 && $0.isPlaying }
        XCTAssertEqual(play.label, "Pause")
        capture("Timeline — ready seek and play")

        app.buttons["timeline.fixture.fail"].tap()
        _ = try waitForReport { !$0.isLoading && !$0.isPlaying && $0.phase == "failed" }
        XCTAssertFalse(loading.exists)
        XCTAssertTrue(slider.exists)
        capture("Timeline — local failure stops loading")
        app.buttons["timeline.fixture.start"].tap()
        _ = try waitForReport { $0.isLoading && $0.starts == 2 }
        XCTAssertEqual(try assertLoading(), originalFrame)
        captureFrames("explicit local retry")
        play.tap()
        let paused = try waitForReport { !$0.isLoading && $0.playActions == 2 && $0.phase == "paused" }
        XCTAssertFalse(paused.isPlaying)
        XCTAssertEqual(paused.position, sought.position, accuracy: 0.001)
        XCTAssertFalse(loading.exists)
        XCTAssertEqual(play.label, "Afspil")
        capture("Timeline — pause loading callback")
        XCTAssertEqual(app.staticTexts["timeline.fixture.firebase"].label, "Firebase: ikke startet")
    }

    func testReducedAndInactiveLoadingTimelineIsStatic() throws {
        let originalFrame = try assertLoading()
        toggle("timeline.fixture.reduced", to: true)
        _ = try waitForReport { $0.reduceMotionOverride && $0.isLoading }
        XCTAssertEqual(try assertLoading(), originalFrame)
        captureFrames("reduced static loading")
        toggle("timeline.fixture.reduced", to: false)
        toggle("timeline.fixture.inactive", to: true)
        _ = try waitForReport { $0.inactiveOverride && $0.isLoading }
        XCTAssertEqual(try assertLoading(), originalFrame)
        captureFrames("injected inactive static loading")
        toggle("timeline.fixture.inactive", to: false)
        _ = try waitForReport { !$0.inactiveOverride && $0.isLoading }
        captureFrames("returned active loading")
        let after = try XCTUnwrap(report())
        XCTAssertEqual(after.position, 0.35, accuracy: 0.001)
        XCTAssertEqual(after.seekCommits, 0)
        XCTAssertEqual(after.playActions, 0)
        app.buttons["timeline.fixture.ready"].tap()
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        XCTAssertFalse(loading.exists)
        XCTAssertEqual(app.activityIndicators.count, 0)
        capture("Timeline — ready after local motion transitions")
        XCTAssertEqual(app.staticTexts["timeline.fixture.firebase"].label, "Firebase: ikke startet")
    }

    private var fullDiagnostic: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "full.player.fixture.report").firstMatch
    }

    private func fullReport() -> [String: Any]? {
        guard fullDiagnostic.exists, let text = fullDiagnostic.value as? String,
              let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func fullFrame(_ key: String, in report: [String: Any]) -> CGRect? {
        guard let frames = report["frames"] as? [String: [String: Double]], let value = frames[key],
              let x = value["x"], let y = value["y"], let width = value["width"], let height = value["height"] else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    @discardableResult
    private func waitForFullReport(_ predicate: ([String: Any]) -> Bool) throws -> [String: Any] {
        for _ in 0..<50 {
            if let value = fullReport(), predicate(value) { return value }
            Thread.sleep(forTimeInterval: 0.1)
        }
        captureFullPlayer("state did not settle")
        XCTFail("Expected complete player fixture state was not observed")
        return try XCTUnwrap(fullReport())
    }

    private func captureFullPlayer(_ phase: String) {
        // Application screenshots may crop a landscape sheet. The actual screen
        // preserves its window; UIImage drawing honors any orientation metadata.
        let screen = XCUIScreen.main.screenshot()
        let image = screen.image
        let picture: XCTAttachment
        if image.imageOrientation == .up {
            picture = XCTAttachment(screenshot: screen)
        } else {
            let format = UIGraphicsImageRendererFormat(); format.scale = image.scale
            let upright = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: image.size))
            }
            picture = XCTAttachment(image: upright)
        }
        picture.name = "Full player — \(phase)"; picture.lifetime = .keepAlways; add(picture)
        var state = fullReport() ?? ["missingPlayerReport": true]
        state["capture"] = ["deviceOrientation": XCUIDevice.shared.orientation.rawValue,
                            "sourceImageOrientation": image.imageOrientation.rawValue,
                            "screenImageWidth": image.size.width, "screenImageHeight": image.size.height]
        let bytes = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
        let attachment = XCTAttachment(string: bytes.map { String(decoding: $0, as: UTF8.self) } ?? "invalid local diagnostic")
        attachment.name = "Full player — \(phase) — actual geometry and callbacks"
        attachment.lifetime = .keepAlways; add(attachment)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Full player — \(phase) — actual accessibility tree"
        tree.lifetime = .keepAlways; add(tree)
    }

    private var fullScroll: XCUIElement { app.scrollViews["podcast.full.scroll"] }
    private func fullViewport(_ report: [String: Any]) -> CGRect? {
        guard let host = fullFrame("sheet", in: report), let scroll = fullFrame("viewport", in: report) else { return nil }
        return host.intersection(scroll).intersection(app.frame)
    }
    private func fullElement(_ key: String) -> XCUIElement {
        if key == "timeline" { return (fullReport()?["isLoading"] as? Bool) == true ? loading : slider }
        if key == "play" { return play }
        if key == "volume" { return app.sliders["podcast.full.volume"] }
        if key == "title" { return app.descendants(matching: .any).matching(identifier: "podcast.full.title").firstMatch }
        if ["category", "author"].contains(key) { return app.staticTexts["podcast.full.\(key)"] }
        if key == "ai" { return app.descendants(matching: .any).matching(identifier: "podcast.full.ai").firstMatch }
        return app.buttons["podcast.full.\(key)"]
    }
    private func panFullPlayer(in viewport: CGRect, upward: Bool, distance requested: CGFloat) {
        // Pan from actual visible text/artwork, as a finger would. The margin
        // gesture oscillated even when moved away from the drawn indicator.
        // Never begin on a button/Slider or invent an off-content safe point.
        let distance = min(max(50, requested), viewport.height * 0.55)
        let run = CGRect(x: viewport.minX + 8,
                         y: viewport.minY + 16 + (upward ? distance : 0),
                         width: viewport.width - 16, height: viewport.height - 32 - distance)
        let report = fullReport() ?? [:]
        let visibleContent = ["author", "title", "category", "artwork"].compactMap { key -> CGRect? in
            guard let frame = fullFrame(key, in: report) else { return nil }
            let visible = frame.intersection(run)
            return !visible.isNull && visible.width > 16 && visible.height > 2 ? visible : nil
        }.first
        guard let visibleContent else {
            captureFullPlayer("No visible non-interactive content for native pan")
            XCTFail("A native pan needs an actual text/artwork start with room inside the viewport")
            return
        }
        let point = CGPoint(x: visibleContent.midX, y: visibleContent.midY)
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y))
        let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y + (upward ? -distance : distance)))
        start.press(forDuration: 0.08, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        Thread.sleep(forTimeInterval: 0.15)
    }
    private func waitForFullHittability(_ key: String) -> Bool {
        // Geometry arrives before the accessibility tree after a native pan.
        for attempt in 0...5 {
            let element = fullElement(key)
            if element.exists && element.isHittable { return true }
            if attempt < 5 { Thread.sleep(forTimeInterval: 0.1) }
        }
        return false
    }
    private func recordFullReveal(_ key: String, success: Bool, reason: String,
                                  pans: Int, positions: [[String: Any]]) {
        let report = fullReport() ?? [:]
        let frame = fullFrame(key, in: report) ?? .null
        let viewport = fullViewport(report) ?? .null
        let element = fullElement(key)
        let exists = element.exists
        let hit = exists && element.isHittable
        let contained = !frame.isNull && !viewport.isNull && viewport.insetBy(dx: -0.5, dy: -0.5).contains(frame)
        let describe: (CGRect) -> String = { rect in
            guard !rect.isNull else { return "missing" }
            return String(format: "%.1f,%.1f %.1fx%.1f", Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height))
        }
        let title = "Full player reveal \(key): \(success ? "pass" : "FAIL") \(reason), pans=\(pans), frame=\(describe(frame)), viewport=\(describe(viewport)), full=\(contained), exists=\(exists), hit=\(hit)"
        XCTContext.runActivity(named: title) { activity in
            let data: [String: Any] = ["key": key, "success": success, "reason": reason,
                                      "pans": pans, "wholeFrameContained": contained, "exists": exists, "hittable": hit,
                                      "positions": positions, "report": report]
            let bytes = try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys])
            let attachment = XCTAttachment(string: bytes.map { String(decoding: $0, as: UTF8.self) } ?? "invalid reveal diagnostic")
            attachment.name = "Final measured frame, viewport, native AX and callbacks"
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
        if !success { captureFullPlayer("FAILED reveal \(key) — \(reason)") }
    }
    private func revealFullPlayer(_ key: String, topEdgeOnly: Bool = false,
                                  requiresHittability: Bool = false) -> Bool {
        var previousFrame: CGRect?
        var previousViewport: CGRect?
        var unchanged = 0
        var positions: [[String: Any]] = []
        var pans = 0
        var failure = "eight-pan limit"
        let near: (CGRect, CGRect) -> Bool = { a, b in
            abs(a.minX - b.minX) <= 0.5 && abs(a.minY - b.minY) <= 0.5 &&
                abs(a.width - b.width) <= 0.5 && abs(a.height - b.height) <= 0.5
        }
        let isContained: (CGRect, CGRect) -> Bool = { frame, viewport in
            let horizontal = frame.minX >= viewport.minX - 0.5 && frame.maxX <= viewport.maxX + 0.5
            return topEdgeOnly
                ? horizontal && frame.minY >= viewport.minY - 0.5 && frame.minY < viewport.maxY - 44
                : viewport.insetBy(dx: -0.5, dy: -0.5).contains(frame)
        }
        for attempt in 0...8 {
            guard let report = fullReport(), let viewport = fullViewport(report), !viewport.isEmpty,
                  let frame = fullFrame(key, in: report), !frame.isEmpty else {
                failure = "missing actual geometry"; break
            }
            positions.append(["attempt": attempt,
                              "frame": [frame.minX, frame.minY, frame.width, frame.height],
                              "viewport": [viewport.minX, viewport.minY, viewport.width, viewport.height]])
            let contained = isContained(frame, viewport)
            if contained {
                if !requiresHittability || waitForFullHittability(key) {
                    // The AX wait must not authorize a frame that moved meanwhile.
                    if let settled = fullReport(), let actual = fullFrame(key, in: settled),
                       let bounds = fullViewport(settled), near(actual, frame), near(bounds, viewport),
                       isContained(actual, bounds),
                       (!requiresHittability || fullElement(key).isHittable) {
                        recordFullReveal(key, success: true, reason: topEdgeOnly ? "top visible" : "whole frame visible",
                                         pans: pans, positions: positions)
                        return true
                    }
                    failure = "geometry changed during accessibility settlement"
                    continue
                } else {
                    failure = "whole frame visible but native control not hittable"; break
                }
            }
            if let previousFrame, let previousViewport,
               near(frame, previousFrame), near(viewport, previousViewport) { unchanged += 1 }
            else { unchanged = 0 }
            if unchanged >= 2 { failure = "two unchanged native positions"; break }
            guard attempt < 8 else { break }
            previousFrame = frame; previousViewport = viewport
            let upward: Bool
            let distance: CGFloat
            if frame.minY < viewport.minY { upward = false; distance = viewport.minY - frame.minY + 8 }
            else { upward = true; distance = topEdgeOnly ? frame.minY - viewport.minY : frame.maxY - viewport.maxY + 8 }
            panFullPlayer(in: viewport, upward: upward, distance: distance)
            pans += 1
        }
        recordFullReveal(key, success: false, reason: failure, pans: pans, positions: positions)
        return false
    }
    private func captureFullMetadata(_ key: String, phase: String) throws -> [String] {
        guard let original = fullReport(), let viewport = fullViewport(original),
              let frame = fullFrame(key, in: original) else { return ["\(phase): missing \(key) geometry"] }
        if frame.height <= viewport.height + 0.5 {
            let revealed = revealFullPlayer(key)
            captureFullPlayer("\(phase) — full \(key)")
            return revealed ? [] : ["\(phase): complete \(key) could not be revealed inside the sheet"]
        }
        // A wrapped title can be taller than a landscape viewport at AX5.
        // Verify complete top-to-bottom coverage in overlapping real images;
        // requiring its entire height at once would force clipping/font scaling.
        guard revealFullPlayer(key, topEdgeOnly: true) else {
            captureFullPlayer("\(phase) — missing \(key) top")
            return ["\(phase): \(key) top could not be reached"]
        }
        var covered: CGFloat = 0
        var unchanged = 0
        for index in 0...8 {
            let report = try XCTUnwrap(fullReport())
            let visible = try XCTUnwrap(fullViewport(report))
            let current = try XCTUnwrap(fullFrame(key, in: report))
            let intersection = current.intersection(visible)
            captureFullPlayer("\(phase) — \(key) text segment \(index + 1)")
            guard current.minX >= visible.minX - 0.5, current.maxX <= visible.maxX + 0.5,
                  !intersection.isNull, intersection.minY - current.minY <= covered + 0.5 else {
                return ["\(phase): \(key) text coverage contains a gap or horizontal clipping"]
            }
            let nextCovered = max(covered, intersection.maxY - current.minY)
            unchanged = nextCovered - covered <= 0.5 ? unchanged + 1 : 0
            covered = nextCovered
            if covered >= current.height - 0.5 { return [] }
            if unchanged >= 2 || index == 8 {
                recordFullReveal(key, success: false, reason: unchanged >= 2 ? "two unchanged metadata positions" : "eight-pan metadata limit",
                                 pans: index, positions: [])
                break
            }
            panFullPlayer(in: visible, upward: true, distance: visible.height * 0.5)
        }
        return ["\(phase): \(key) ending was not reached within bounded scrolling"]
    }

    private func fullPlayerLayoutIssues(_ phase: String, report: [String: Any]) -> [String] {
        var issues: [String] = []
        guard let sheet = fullFrame("sheet", in: report), !sheet.isEmpty else { return ["\(phase): missing actual sheet bounds"] }
        let controls = ["options", "timeline", "rate", "backward", "play", "forward", "sleep", "share", "route", "queue"]
        for key in ["artwork", "category", "title", "author"] + controls {
            guard let frame = fullFrame(key, in: report), !frame.isEmpty else {
                issues.append("\(phase): \(key) has no visible geometry"); continue
            }
            if controls.contains(key), frame.width < 43.5 || frame.height < 43.5 {
                issues.append("\(phase): \(key) is below the44pt target: \(frame.size)")
            }
        }
        for (upper, lower) in [("artwork", "category"), ("category", "title"), ("title", "author"), ("author", "timeline"), ("timeline", "play")] {
            if let a = fullFrame(upper, in: report), let b = fullFrame(lower, in: report), a.maxY > b.minY + 0.5 {
                issues.append("\(phase): \(upper) overlaps \(lower)")
            }
        }
        for (left, right) in [("rate", "backward"), ("backward", "play"), ("play", "forward"), ("forward", "sleep")] {
            if let a = fullFrame(left, in: report), let b = fullFrame(right, in: report), a.maxX > b.minX + 0.5 {
                issues.append("\(phase): \(left) overlaps \(right)")
            }
        }
        return issues
    }

    private func inspectReachableFullPlayer(_ phase: String, narrated: Bool) throws -> [String] {
        var issues = fullPlayerLayoutIssues(phase, report: try XCTUnwrap(fullReport()))
        for key in ["artwork", "category", "title", "author"] + (narrated ? ["ai"] : []) {
            issues += try captureFullMetadata(key, phase: phase)
        }
        for key in ["options", "timeline", "rate", "backward", "play", "forward", "sleep", "share", "route", "queue"] {
            let interactive = key != "timeline" || (fullReport()?["isLoading"] as? Bool) != true
            let revealed = revealFullPlayer(key, requiresHittability: interactive)
            if !revealed || !fullElement(key).exists || (interactive && !fullElement(key).isHittable) {
                issues.append("\(phase): actual \(key) is not wholly visible and hittable after bounded scrolling")
            }
            if ["timeline", "rate", "queue"].contains(key) { captureFullPlayer("\(phase) — reachable \(key)") }
        }
        return issues
    }
    private func requireFullControl(_ key: String, phase: String) throws -> XCUIElement {
        let revealed = revealFullPlayer(key, requiresHittability: true)
        captureFullPlayer("\(phase) — before \(key) action")
        XCTAssertTrue(revealed, "The whole measured \(key) control must be inside the actual sheet immediately before use")
        let report = try XCTUnwrap(fullReport())
        let viewport = try XCTUnwrap(fullViewport(report))
        let frame = try XCTUnwrap(fullFrame(key, in: report))
        XCTAssertTrue(viewport.insetBy(dx: -0.5, dy: -0.5).contains(frame))
        XCTAssertGreaterThanOrEqual(frame.width, 43.5)
        XCTAssertGreaterThanOrEqual(frame.height, 43.5)
        let element = fullElement(key)
        XCTAssertTrue(element.exists && element.isHittable)
        return element
    }

    func testFullPlayerSheetCoverGlowVariants() throws {
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        for variant in 0...6 {
            app.terminate()
            app.launchArguments += ["-AproposCoverVariant", String(variant)]
            // Launch into the intended orientation instead of tapping during
            // an accessibility-sized layout's landscape-to-portrait transition.
            XCUIDevice.shared.orientation = .portrait
            app.launch()
            let open = app.buttons["full.player.fixture.open"]
            XCTAssertTrue(open.waitForExistence(timeout: 10) && open.isHittable)
            open.tap()
            _ = try waitForFullReport {
                self.fullFrame("artwork", in: $0) != nil && self.fullFrame("timeline", in: $0) != nil
                    && self.fullFrame("ambient", in: $0) != nil && self.fullFrame("sheet", in: $0) != nil
            }
            for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
                XCUIDevice.shared.orientation = orientation
                Thread.sleep(forTimeInterval: 0.6)
                let report = try XCTUnwrap(fullReport())
                let artwork = try XCTUnwrap(fullFrame("artwork", in: report))
                let timeline = try XCTUnwrap(fullFrame("timeline", in: report))
                let ambient = try XCTUnwrap(fullFrame("ambient", in: report))
                let sheet = try XCTUnwrap(fullFrame("sheet", in: report))
                // Ignoring safe areas may extend beyond the host, but the
                // colored backdrop must cover the actual sheet, not the cover.
                XCTAssertTrue(ambient.insetBy(dx: -1, dy: -1).contains(sheet))
                XCTAssertGreaterThanOrEqual(ambient.height, sheet.height - 1)
                XCTAssertGreaterThanOrEqual(ambient.width, sheet.width - 1)
                // The artwork probe includes its 20pt presentation padding.
                XCTAssertEqual(artwork.minX + 20, timeline.minX, accuracy: 1)
                XCTAssertEqual(artwork.maxX - 20, timeline.maxX, accuracy: 1)
                XCTAssertGreaterThan(artwork.width - 40, 320)
                XCTAssertEqual(artwork.height, artwork.width - 40, accuracy: 1)
                let screenSize = XCUIScreen.main.screenshot().image.size
                if orientation == .landscapeLeft { XCTAssertGreaterThan(screenSize.width, screenSize.height) }
                else { XCTAssertGreaterThan(screenSize.height, screenSize.width) }
                XCTAssertEqual(report["artworkVariant"] as? Int, variant)
                XCTAssertEqual(report["firebaseStarted"] as? Bool, false)
                XCTAssertFalse(app.sliders["podcast.full.volume"].exists)
                XCTAssertTrue(revealFullPlayer("artwork", topEdgeOnly: true))
                captureFullPlayer("cover variant \(variant) — \(orientation.rawValue)")
            }
            app.launchArguments.removeLast(2)
        }
    }

    func testFullPlayerSheetAmbientTitleMotionAndFallback() throws {
        try exerciseAmbientTitle(expectReducedMotion: false, shortTitle: false)
    }

    func testReducedFullPlayerSheetAmbientTitleMotionAndFallback() throws {
        try exerciseAmbientTitle(expectReducedMotion: true, shortTitle: false)
    }

    func testFullPlayerSheetShortTitleIsStatic() throws {
        try exerciseAmbientTitle(expectReducedMotion: false, shortTitle: true)
    }

    /// Phone-only traversal of a moderately overflowing title. The real clock
    /// and glyph transform must reach both ends; no injected phase or timer.
    func testFullPlayerSheetTraversalRevealsEndAndReturns() throws {
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        XCUIDevice.shared.orientation = .portrait
        XCTAssertLessThan(XCUIScreen.main.screenshot().image.size.width, 600)
        let open = app.buttons["full.player.fixture.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 10) && open.isHittable)
        open.tap()
        let initial = try waitForFullReport {
            self.fullFrame("title", in: $0) != nil && self.fullFrame("title.glyph", in: $0) != nil
        }
        XCTAssertEqual(initial["reduceMotion"] as? Bool, false)
        XCTAssertFalse((initial["dynamicType"] as? String ?? "").lowercased().contains("accessibility"))
        let title = try XCTUnwrap(initial["title"] as? String)
        XCTAssertEqual(title, "Apropos Magazine · Film, musik og kultur")
        XCTAssertEqual(fullElement("title").label, title)
        XCTAssertTrue(revealFullPlayer("title"))
        let baseline = try XCTUnwrap(fullReport())
        let container = try XCTUnwrap(fullFrame("title", in: baseline))
        let glyph = try XCTUnwrap(fullFrame("title.glyph", in: baseline))
        XCTAssertGreaterThan(glyph.width, container.width + 1)
        XCTAssertTrue(try XCTUnwrap(fullViewport(baseline)).insetBy(dx: -1, dy: -1).contains(container))
        captureFullPlayer("title traversal — actual starting presentation")
        // The same deadline bounds reaching the right end, its pause, and the
        // return to the left end, including AX sampling and both end captures.
        let deadline = Date().addingTimeInterval(24)
        var endState: [String: Any]?
        while Date() < deadline {
            if let report = fullReport(), let frame = fullFrame("title.glyph", in: report),
               abs(frame.maxX - container.maxX) <= 1.5 {
                endState = report; break
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
        guard let endState else {
            captureFullPlayer("title traversal — failed to reach actual right end")
            XCTFail("The real title did not reveal its ending within the traversal deadline")
            return
        }
        captureFullPlayer("title traversal — actual complete ending at right edge")
        var returnedState: [String: Any]?
        while Date() < deadline {
            if let report = fullReport(), let frame = fullFrame("title.glyph", in: report),
               abs(frame.minX - container.minX) <= 1.5 {
                returnedState = report; break
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
        guard let returnedState else {
            captureFullPlayer("title traversal — failed to return to actual left end")
            XCTFail("The real title did not return to its beginning within the traversal deadline")
            return
        }
        captureFullPlayer("title traversal — actual return to complete beginning")
        for report in [endState, returnedState] {
            let frame = try XCTUnwrap(fullFrame("title", in: report))
            XCTAssertEqual(frame.minX, container.minX, accuracy: 1)
            XCTAssertEqual(frame.width, container.width, accuracy: 1)
            XCTAssertEqual(report["position"] as? Double, baseline["position"] as? Double)
            XCTAssertEqual(report["playActions"] as? Int, 0)
            XCTAssertEqual(report["seekCommits"] as? Int, 0)
            XCTAssertEqual(report["queueSelections"] as? Int, 0)
            XCTAssertEqual(report["firebaseStarted"] as? Bool, false)
        }
        XCTAssertEqual(fullElement("title").label, title)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "podcast.full.title").count, 1)
    }

    private func exerciseAmbientTitle(expectReducedMotion: Bool, shortTitle: Bool) throws {
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        XCUIDevice.shared.orientation = .portrait
        let open = app.buttons["full.player.fixture.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 10) && open.isHittable)
        open.tap()
        let initial = try waitForFullReport {
            self.fullFrame("title", in: $0) != nil && self.fullFrame("title.glyph", in: $0) != nil
                && self.fullFrame("ambient", in: $0) != nil
        }
        XCTAssertEqual(initial["firebaseStarted"] as? Bool, false)
        XCTAssertEqual(initial["reduceMotion"] as? Bool, expectReducedMotion)
        let largeText = (initial["dynamicType"] as? String ?? "").lowercased().contains("accessibility")
        let staticTitle = expectReducedMotion || largeText || shortTitle
        let title = try XCTUnwrap(initial["title"] as? String)
        XCTAssertEqual(fullElement("title").label, title)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "podcast.full.title").count, 1)
        if staticTitle {
            let issues = try captureFullMetadata("title", phase: "static complete title")
            XCTAssertTrue(issues.isEmpty, issues.joined(separator: "\n"))
        }
        XCTAssertTrue(revealFullPlayer("title", topEdgeOnly: staticTitle))
        // Allow the intentional two-second end hold to pass before comparing
        // multiple real presentation frames. No fixture offset/clock authority.
        Thread.sleep(forTimeInterval: 2.2)
        var samples: [CGRect] = []
        var containers: [CGRect] = []
        for index in 0..<3 {
            if index > 0 { Thread.sleep(forTimeInterval: 0.6) }
            let report = try XCTUnwrap(fullReport())
            samples.append(try XCTUnwrap(fullFrame("title.glyph", in: report)))
            containers.append(try XCTUnwrap(fullFrame("title", in: report)))
            XCTAssertEqual(report["position"] as? Double, initial["position"] as? Double)
            XCTAssertEqual(report["playActions"] as? Int, 0)
            XCTAssertEqual(report["seekCommits"] as? Int, 0)
            XCTAssertEqual(report["queueSelections"] as? Int, 0)
            XCTAssertEqual(report["firebaseStarted"] as? Bool, false)
            XCTAssertFalse(app.sliders["podcast.full.volume"].exists)
            XCTAssertEqual(fullElement("title").label, title)
            captureFullPlayer("ambient title \(staticTitle ? "static" : "moving") frame \(index + 1)")
        }
        for container in containers.dropFirst() {
            XCTAssertEqual(container.minX, containers[0].minX, accuracy: 1)
            XCTAssertEqual(container.width, containers[0].width, accuracy: 1)
        }
        if staticTitle {
            for sample in samples.dropFirst() {
                XCTAssertEqual(sample.minX, samples[0].minX, accuracy: 1)
                XCTAssertEqual(sample.minY, samples[0].minY, accuracy: 1)
            }
            if shortTitle { XCTAssertLessThanOrEqual(samples[0].width, containers[0].width + 1) }
        } else {
            XCTAssertGreaterThan(samples[0].width, containers[0].width + 1)
            XCTAssertGreaterThan(abs(samples[2].minX - samples[0].minX), 4)
            XCTAssertEqual(samples[0].height, containers[0].height, accuracy: 1)
        }
    }

    func testFullPlayerSheetControlsAndQueueSurviveRotation() throws {
        try exerciseFullPlayerSheet(narrated: false)
    }
    func testNarratedFullPlayerSheetLoadingAndQueueSurviveRotation() throws {
        try exerciseFullPlayerSheet(narrated: true)
    }
    func testFullPlayerSheetQueueNativeGestureDiagnosis() throws {
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        XCUIDevice.shared.orientation = .portrait
        app.buttons["full.player.fixture.open"].tap()
        XCTAssertTrue(fullDiagnostic.waitForExistence(timeout: 5))
        _ = try waitForFullReport { self.fullFrame("queue", in: $0) != nil }
        try requireFullControl("play", phase: "native queue diagnosis").tap()
        _ = try waitForFullReport { ($0["isPlaying"] as? Bool) == true }
        try requireFullControl("queue", phase: "native queue diagnosis").tap()
        let list = app.descendants(matching: .any).matching(identifier: "podcast.queue.list").firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let native = app.descendants(matching: .any).matching(identifier: "full.player.fixture.queue.native").firstMatch
        XCTAssertTrue(native.waitForExistence(timeout: 5))
        func snapshot(_ phase: String) throws {
            captureFullPlayer("native queue diagnosis — \(phase)")
            let value = try XCTUnwrap(native.value as? String)
            _ = try JSONSerialization.jsonObject(with: Data(value.utf8))
            let attachment = XCTAttachment(string: value)
            attachment.name = "Read-only UIKit queue — \(phase)"
            attachment.lifetime = .keepAlways; add(attachment)
        }
        try snapshot("before container swipe")
        list.swipeUp(velocity: .slow)
        try snapshot("after container swipe")
        let bounds = list.frame.intersection(app.frame)
        let distance = min(220, bounds.height * 0.4)
        let run = CGRect(x: bounds.minX + 8, y: bounds.minY + 16 + distance,
                         width: bounds.width - 16, height: bounds.height - 32 - distance)
        let text = try XCTUnwrap(list.staticTexts.allElementsBoundByIndex.compactMap { element -> CGRect? in
            let visible = element.frame.intersection(run)
            return !visible.isNull && visible.width > 16 && visible.height > 2 ? visible : nil
        }.first)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: text.midX, dy: text.midY))
        let end = origin.withOffset(CGVector(dx: text.midX, dy: text.midY - distance))
        start.press(forDuration: 0.08, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        try snapshot("after actual row-text pan")
        let grabber = app.buttons["Sheet Grabber"].firstMatch
        XCTAssertTrue(grabber.exists && grabber.isHittable)
        let upper = origin.withOffset(CGVector(dx: grabber.frame.midX, dy: max(app.frame.minY + 80, grabber.frame.midY - 400)))
        grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.08, thenDragTo: upper, withVelocity: .slow, thenHoldForDuration: 0.1)
        try snapshot("after actual sheet-grabber drag")
        let second = app.buttons["podcast.queue.episode.full-player-two"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertTrue(second.isHittable)
        second.tap()
        _ = try waitForFullReport { ($0["queueSelections"] as? Int) == 1 && ($0["episodeID"] as? String) == "full-player-two" }
    }

    private func exerciseFullPlayerSheet(narrated: Bool) throws {
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        XCUIDevice.shared.orientation = .portrait
        app.buttons["full.player.fixture.open"].tap()
        XCTAssertTrue(fullDiagnostic.waitForExistence(timeout: 5))
        _ = try waitForFullReport { self.fullFrame("queue", in: $0) != nil && self.fullFrame("viewport", in: $0) != nil }
        Thread.sleep(forTimeInterval: 0.6)
        let initial = try XCTUnwrap(fullReport())
        XCTAssertEqual(initial["firebaseStarted"] as? Bool, false)
        XCTAssertEqual(initial["isNarrated"] as? Bool, narrated)
        XCTAssertEqual(initial["isLoading"] as? Bool, narrated)
        XCTAssertEqual(fullElement("title").label, initial["title"] as? String)
        XCTAssertEqual(app.staticTexts["podcast.full.category"].label, initial["category"] as? String)
        if narrated {
            XCTAssertTrue(fullElement("ai").exists)
            XCTAssertEqual(fullElement("ai").label, "Oplæst med kunstig intelligens")
            XCTAssertTrue(loading.exists)
            XCTAssertEqual(loading.label, "Lyden indlæses")
            XCTAssertEqual(loading.value as? String, "Indlæser")
            XCTAssertFalse(slider.exists)
            XCTAssertEqual(play.label, "Pause indlæsning")
        }
        var issues = try inspectReachableFullPlayer("portrait", narrated: narrated)

        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.app.frame.width > self.app.frame.height }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 8), .completed)
        Thread.sleep(forTimeInterval: 0.6)
        issues += try inspectReachableFullPlayer("landscape", narrated: narrated)
        let rotated = try XCTUnwrap(fullReport())
        XCTAssertEqual(rotated["episodeID"] as? String, initial["episodeID"] as? String)
        XCTAssertEqual(rotated["playActions"] as? Int, 0)
        XCTAssertEqual(rotated["seekCommits"] as? Int, 0)
        XCTAssertEqual(rotated["rateActions"] as? Int, 0)

        XCUIDevice.shared.orientation = .portrait
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.app.frame.height > self.app.frame.width }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 8), .completed)
        Thread.sleep(forTimeInterval: 0.6)
        issues += try inspectReachableFullPlayer("returned portrait", narrated: narrated)
        let returned = try XCTUnwrap(fullReport())
        XCTAssertEqual(returned["episodeID"] as? String, initial["episodeID"] as? String)
        XCTAssertEqual(returned["position"] as? Double, initial["position"] as? Double)
        XCTAssertEqual(returned["playActions"] as? Int, 0)
        XCTAssertEqual(returned["seekCommits"] as? Int, 0)
        XCTAssertEqual(returned["rateActions"] as? Int, 0)

        let playControl = try requireFullControl("play", phase: "returned portrait")
        playControl.tap()
        _ = try waitForFullReport { ($0["playActions"] as? Int) == 1 && ($0["isPlaying"] as? Bool) == !narrated && ($0["isLoading"] as? Bool) == false }
        XCTAssertTrue(slider.exists)
        XCTAssertFalse(loading.exists)
        let seekControl = try requireFullControl("timeline", phase: "ready after local pause/play")
        seekControl.adjust(toNormalizedSliderPosition: 0.70)
        _ = try waitForFullReport { ($0["seekCommits"] as? Int ?? 0) > 0 && ($0["position"] as? Double ?? 0) > 0.55 }
        let rate = try requireFullControl("rate", phase: "ready")
        rate.tap()
        _ = try waitForFullReport { ($0["rateActions"] as? Int) == 1 && ($0["rateLabel"] as? String) == "1.25x" }
        XCTAssertEqual(rate.value as? String, "1.25x")
        captureFullPlayer("complete 1.25x rate text after action")

        let backward = try requireFullControl("backward", phase: "ready")
        backward.tap()
        _ = try waitForFullReport { ($0["backwardActions"] as? Int) == 1 }
        let forward = try requireFullControl("forward", phase: "ready")
        forward.tap()
        _ = try waitForFullReport { ($0["forwardActions"] as? Int) == 1 }
        let share = try requireFullControl("share", phase: "local share callback only")
        share.tap()
        _ = try waitForFullReport { ($0["shareActions"] as? Int) == 1 }
        let sleep = try requireFullControl("sleep", phase: "local sleep callback only")
        sleep.tap()
        let fifteen = app.buttons["15 min"]
        XCTAssertTrue(fifteen.waitForExistence(timeout: 5) && fifteen.isHittable)
        fifteen.tap()
        _ = try waitForFullReport { ($0["sleepActions"] as? Int) == 1 }

        XCTAssertFalse(app.sliders["podcast.full.volume"].exists)
        let localRoute = try requireFullControl("route", phase: "local route slot only")
        localRoute.tap()
        _ = try waitForFullReport { ($0["routeActions"] as? Int) == 1 }

        let queue = try requireFullControl("queue", phase: "ready")
        queue.tap()
        let queueList = app.descendants(matching: .any).matching(identifier: "podcast.queue.list").firstMatch
        XCTAssertTrue(queueList.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(queueList.frame.intersection(app.frame).height, 44)
        let second = app.buttons["podcast.queue.episode.full-player-two"]
        // List can defer creating the second row when the first title fills
        // the accessibility-sized sheet. Reveal it with actual native scrolls.
        captureFullPlayer("actual queue before native row reveal")
        if !second.exists || !second.isHittable {
            // The queue already offers a native large detent. Use its actual
            // grabber for long accessibility rows; never change the viewport
            // or select an episode directly in the fixture/model.
            let grabber = app.buttons["Sheet Grabber"].firstMatch
            XCTAssertTrue(grabber.exists && grabber.isHittable)
            let oldFrame = queueList.frame
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let upper = origin.withOffset(CGVector(dx: grabber.frame.midX,
                                                  dy: max(app.frame.minY + 80, grabber.frame.midY - 400)))
            grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.08, thenDragTo: upper, withVelocity: .slow, thenHoldForDuration: 0.1)
            captureFullPlayer("actual queue after native grabber expansion")
            XCTAssertGreaterThanOrEqual(queueList.frame.height, oldFrame.height - 0.5)
        }
        var previousRows: [String]?
        var unchangedRows = 0
        for attempt in 0...6 {
            if second.exists && second.isHittable { break }
            let rows = queueList.buttons.allElementsBoundByIndex.map {
                "\($0.identifier):\($0.frame)"
            }
            unchangedRows = previousRows == rows ? unchangedRows + 1 : 0
            if attempt == 6 || unchangedRows >= 2 {
                captureFullPlayer("Queue row not revealed after bounded native scrolling")
                break
            }
            previousRows = rows
            // A container's automatic swipe point need not be readable content.
            // Begin on actual visible row text, with both endpoints in the list.
            let bounds = queueList.frame.intersection(app.frame)
            let distance = min(220, bounds.height * 0.4)
            let run = CGRect(x: bounds.minX + 8, y: bounds.minY + 16 + distance,
                             width: bounds.width - 16, height: bounds.height - 32 - distance)
            let text = queueList.staticTexts.allElementsBoundByIndex.compactMap { element -> CGRect? in
                let visible = element.frame.intersection(run)
                return !visible.isNull && visible.width > 16 && visible.height > 2 ? visible : nil
            }.first
            guard let text else {
                captureFullPlayer("Queue has no visible row text for a native content pan")
                XCTFail("Queue reveal requires an actual visible text start, not a synthetic offset")
                break
            }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: text.midX, dy: text.midY))
            let end = origin.withOffset(CGVector(dx: text.midX, dy: text.midY - distance))
            start.press(forDuration: 0.08, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
            captureFullPlayer("actual queue after native row scroll \(attempt + 1)")
        }
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertTrue(second.isHittable)
        captureFullPlayer("actual queue before selecting second episode")
        second.tap()
        let selected = try waitForFullReport { ($0["queueSelections"] as? Int) == 1 && ($0["episodeID"] as? String) == "full-player-two" }
        XCTAssertEqual(selected["queueOpens"] as? Int, 1)
        XCTAssertEqual(selected["position"] as? Double, 0.1)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "podcast.queue.list").firstMatch.exists)
        XCTAssertEqual(fullElement("title").label, "Nye perspektiver på det danske kulturliv")
        XCTAssertEqual(selected["firebaseStarted"] as? Bool, false)
        XCTAssertEqual(selected["artworkVariant"] as? Int, 1)
        XCTAssertTrue(revealFullPlayer("artwork", topEdgeOnly: true))
        captureFullPlayer("cool cover replaces warm cover after actual queue selection")
        issues += try captureFullMetadata("title", phase: "returned from actual queue selection")
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "\n"))
    }
}
