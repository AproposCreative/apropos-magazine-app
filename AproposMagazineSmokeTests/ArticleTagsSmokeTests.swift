import XCTest

final class ArticleTagsSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private let scenarios = ["author", "topic", "word", "mixed"]
    private struct Rect: Decodable {
        let x: Double, y: Double, width: Double, height: Double
        var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    }
    private struct Geometry: Decodable {
        let scenario: String
        let before: Bool
        let frames: [String: Rect]
        let labels: [String: String]
        let environmentAccessibility: Bool
        let systemAccessibility: Bool
        let systemCategory: String
        let bodyState: String
        let prepareCalls: Int
        let probes: Int
        let fetches: Int
        let writes: Int
        let redraws: Int
        let authorTaps: Int
        let leaseID: String
        let statusVisible: Bool
    }

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate(); app = nil }

    private func launch(_ scenario: String, before: Bool) throws -> Geometry {
        app?.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposArticleTagsSmoke", "-ArticleTagsScenario", scenario]
        if before { app.launchArguments.append("-ArticleTagsBefore") }
        app.launch()
        XCTAssertTrue(app.staticTexts["tags.firebase"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["tags.firebase"].label, "Firebase: ikke startet")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Klar'"), object: app.staticTexts["tags.ready"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
        let value = try geometry()
        XCTAssertEqual(value.scenario, scenario)
        XCTAssertEqual(value.before, before)
        XCTAssertEqual(value.environmentAccessibility, value.systemAccessibility,
                       "Shipped tags must inherit the actual system size; only fixture diagnostics are clamped")
        return value
    }

    private func geometry() throws -> Geometry {
        let string = try XCTUnwrap(app.staticTexts["tags.geometry"].value as? String)
        return try JSONDecoder().decode(Geometry.self, from: Data(string.utf8))
    }

    private func frame(_ id: String, in value: Geometry) throws -> CGRect {
        try XCTUnwrap(value.frames[id], "Missing rendered geometry \(id)").frame
    }

    private func evidence(_ value: Geometry, before: Bool) throws {
        let container = try frame("container", in: value)
        let viewport = app.scrollViews["tags.scroll"].frame
        // Every scenario has only one long label, so even maximum text is captured fully.
        XCTAssertGreaterThanOrEqual(container.minY, viewport.minY - 1)
        XCTAssertLessThanOrEqual(container.maxY, viewport.maxY + 1)
        let raw = try XCTUnwrap(app.staticTexts["tags.geometry"].value as? String)
        var observations: [String] = []
        for id in value.labels.keys.sorted() {
            let chip = try frame("chip." + id, in: value), text = try frame("text." + id, in: value)
            let horizontalOverflow = max(0, container.minX - chip.minX) + max(0, chip.maxX - container.maxX)
            let verticalTextOverflow = max(0, chip.minY - text.minY) + max(0, text.maxY - chip.maxY)
            observations.append("\(id): horizontal overflow \(horizontalOverflow) pt; text outside pill vertically \(verticalTextOverflow) pt")
        }
        let phase = value.scenario.hasPrefix("saved") ? " — \(value.bodyState) — status \(value.statusVisible ? "synlig" : "skjult")" : ""
        let note = XCTAttachment(string: raw + "\n" + observations.joined(separator: "\n"))
        note.name = "\(before ? "Before" : "After") tag geometry — \(value.scenario) — \(value.systemCategory)" + phase
        note.lifetime = .keepAlways; add(note)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "\(before ? "Førmåling" : "Artikelmærker") — \(value.scenario) — \(value.systemCategory)" + phase
        screenshot.lifetime = .keepAlways; add(screenshot)
    }

    /// Explicit measurement mode deliberately records old overflow instead of hiding a known regression.
    func testBeforeMeasurementOfActualTagAndTextFrames() throws {
        for scenario in scenarios {
            let value = try launch(scenario, before: true)
            try evidence(value, before: true)
        }
    }

    func testTagsFitAndWrapAtActualSystemTextSizeWithAuthorActionPreserved() throws {
        for scenario in scenarios {
            let value = try launch(scenario, before: false)
            try evidence(value, before: false)
            let container = try frame("container", in: value)
            XCTAssertEqual(container.minX, app.frame.minX + 16, accuracy: 1)
            XCTAssertEqual(container.maxX, app.frame.maxX - 16, accuracy: 1)
            let ids = value.labels.keys.sorted()
            for id in ids {
                let chip = try frame("chip." + id, in: value), text = try frame("text." + id, in: value)
                XCTAssertGreaterThanOrEqual(chip.minX, container.minX - 1, id)
                XCTAssertLessThanOrEqual(chip.maxX, container.maxX + 1, id)
                XCTAssertGreaterThanOrEqual(chip.height + 0.001, 22, id)
                XCTAssertGreaterThanOrEqual(text.minX, chip.minX - 1, id)
                XCTAssertLessThanOrEqual(text.maxX, chip.maxX + 1, id)
                XCTAssertGreaterThanOrEqual(text.minY, chip.minY - 1, id)
                XCTAssertLessThanOrEqual(text.maxY, chip.maxY + 1, id)
            }
            for (offset, leftID) in ids.enumerated() {
                for rightID in ids.dropFirst(offset + 1) {
                    let left = try frame("chip." + leftID, in: value)
                    let right = try frame("chip." + rightID, in: value)
                    XCTAssertFalse(left.insetBy(dx: 0.5, dy: 0.5).intersects(right.insetBy(dx: 0.5, dy: 0.5)),
                                   "Pills must not overlap: \(leftID), \(rightID)")
                }
            }
            if scenario != "mixed" {
                let shortText = try frame("text.short", in: value), longText = try frame("text.long", in: value)
                XCTAssertGreaterThan(longText.height, shortText.height * 1.5, "The long full label must actually wrap, not merely have an untruncated accessibility label")
            } else if value.systemCategory == "UICTContentSizeCategoryL" {
                for id in ids { XCTAssertEqual(try frame("chip." + id, in: value).height, 22, accuracy: 1) }
            }
            if scenario == "author" || scenario == "mixed" {
                let author = app.buttons["tags.author"]
                XCTAssertTrue(author.isHittable)
                author.tap()
                let delivered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Forfattertryk: 1'"), object: app.staticTexts["tags.authorTaps"])
                XCTAssertEqual(XCTWaiter.wait(for: [delivered], timeout: 3), .completed)
                XCTAssertEqual(app.staticTexts["tags.firebase"].label, "Firebase: ikke startet")
            }
        }
    }
    private func waitSavedState(_ state: String, prepareCalls: Int = 1,
                                file: StaticString = #filePath, line: UInt = #line) throws -> Geometry {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            guard let value = try? self?.geometry() else { return false }
            return value.bodyState == state && value.prepareCalls == prepareCalls
        }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: 8)
        if result != .completed {
            let diagnostic = XCTAttachment(string: app.staticTexts["tags.geometry"].value as? String ?? "Missing geometry")
            diagnostic.name = "Unmet saved state: \(state), expected prepare calls \(prepareCalls)"
            diagnostic.lifetime = .keepAlways; add(diagnostic)
            let screen = XCTAttachment(screenshot: app.screenshot())
            screen.name = "Saved-state diagnostic viewport"; screen.lifetime = .keepAlways; add(screen)
        }
        XCTAssertEqual(result, .completed, file: file, line: line)
        return try geometry()
    }

    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 4), file: file, line: line)
        XCTAssertTrue(button.isEnabled, file: file, line: line)
        XCTAssertTrue(button.isHittable, file: file, line: line)
        button.tap()
    }

    private func assertSavedRows(_ value: Geometry, includesSaved: Bool = true,
                                 file: StaticString = #filePath, line: UInt = #line) throws {
        let container = try frame("container", in: value)
        let orderedKeys = value.labels.keys.sorted { left, right in
            if left == "author" { return right != "author" }
            if right == "author" { return false }
            return left < right
        }.map { "chip." + $0 } + (includesSaved ? ["status"] : [])
        let chips = try orderedKeys.map { try frame($0, in: value) }
        XCTAssertFalse(chips.isEmpty, file: file, line: line)
        var rows: [[CGRect]] = []
        for chip in chips {
            XCTAssertGreaterThanOrEqual(chip.minX, container.minX - 0.5, file: file, line: line)
            XCTAssertLessThanOrEqual(chip.maxX, container.maxX + 0.5, file: file, line: line)
            XCTAssertGreaterThanOrEqual(chip.height + 0.001, 22, file: file, line: line)
            if let last = rows.last, let first = last.first, abs(first.midY - chip.midY) < 0.5 {
                rows[rows.count - 1].append(chip)
            } else { rows.append([chip]) }
        }
        var previous: CGRect?
        for row in rows {
            let hull = row.dropFirst().reduce(row[0]) { $0.union($1) }
            XCTAssertEqual(hull.midX, container.midX, accuracy: 0.5,
                "Every actual row, including GEMT alone, remains centered", file: file, line: line)
            for pair in zip(row, row.dropFirst()) {
                XCTAssertEqual(pair.1.minX - pair.0.maxX, 8, accuracy: 0.5, file: file, line: line)
            }
            if let previous {
                XCTAssertEqual(hull.minY - previous.maxY, 8, accuracy: 0.5,
                    "Wrapping uses the same eight-point vertical spacing", file: file, line: line)
            } else { XCTAssertEqual(hull.minY, container.minY, accuracy: 0.5, file: file, line: line) }
            previous = hull
        }
        XCTAssertEqual(try XCTUnwrap(previous).maxY, container.maxY, accuracy: 0.5,
            "An absent status cannot leave an empty row or trailing spacing", file: file, line: line)
        if includesSaved {
            let saved = try frame("status", in: value)
            XCTAssertLessThan(saved.width, container.width,
                "GEMT uses the chip's natural width, not a leading full-width wrapper", file: file, line: line)
            XCTAssertEqual(app.staticTexts["offline.body.status"].label, "GEMT", file: file, line: line)
            if let categoryID = value.labels.keys.first(where: { $0.hasPrefix("category.") }) {
                XCTAssertEqual(saved.height, try frame("chip." + categoryID, in: value).height, accuracy: 0.5,
                    "Short saved/category labels use the same ArticleTagChip", file: file, line: line)
            }
        }
    }

    func testSavedPillSharesCenteredAuthorCategoryFlowAndHasNoEmptySlot() throws {
        for scenario in ["savedMixed", "savedOnly", "savedLong"] {
            _ = try launch(scenario, before: false)
            let checking = try waitSavedState("checking")
            let lease = checking.leaseID
            XCTAssertFalse(lease.isEmpty); XCTAssertEqual(checking.probes, 1)
            tap("tags.releaseProbe")
            let value = try waitSavedState("available")
            XCTAssertEqual(value.leaseID, lease); XCTAssertEqual(value.probes, 1)
            try assertSavedRows(value)
            if scenario == "savedMixed", value.systemCategory == "UICTContentSizeCategoryL" {
                let saved = try frame("status", in: value)
                XCTAssertEqual(saved.midY, try frame("chip.author", in: value).midY, accuracy: 0.5)
                XCTAssertEqual(saved.midY, try frame("chip.category.0", in: value).midY, accuracy: 0.5,
                    "Normal-sized GEMT shares the author's/category's actual row")
            }
            if scenario == "savedOnly" {
                XCTAssertEqual(try frame("status", in: value).midX, try frame("container", in: value).midX, accuracy: 0.5)
            }
            if scenario == "savedLong" {
                XCTAssertGreaterThan(try frame("text.author", in: value).height,
                    try frame("text.category.0", in: value).height * 1.5,
                    "The long visible author name must wrap, not merely have a full AX label")
            }
            try evidence(value, before: false)
            if scenario != "savedOnly" {
                tap("article.header.author")
                let author = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Forfattertryk: 1'"), object: app.staticTexts["tags.authorTaps"])
                XCTAssertEqual(XCTWaiter.wait(for: [author], timeout: 3), .completed)
                XCTAssertEqual(try geometry().prepareCalls, 1)
            }
            if scenario == "savedMixed" {
                tap("tags.hideStatus")
                let absent = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == NO"), object: app.staticTexts["offline.body.status"])
                XCTAssertEqual(XCTWaiter.wait(for: [absent], timeout: 4), .completed)
                let withoutStatus = try geometry()
                XCTAssertFalse(withoutStatus.statusVisible)
                try assertSavedRows(withoutStatus, includesSaved: false)
                try evidence(withoutStatus, before: false)
            }
            XCTAssertEqual(app.staticTexts["tags.firebase"].label, "Firebase: ikke startet")
        }
    }

    func testSavedStatusKeepsOriginalLifecycleThroughProbeFailureAndRetry() throws {
        _ = try launch("savedTransition", before: false)
        let checking = try waitSavedState("checking")
        let lease = checking.leaseID
        XCTAssertFalse(lease.isEmpty); XCTAssertEqual(checking.probes, 1)
        XCTAssertEqual(try frame("status", in: checking).width, try frame("container", in: checking).width, accuracy: 0.5)
        try evidence(checking, before: false)
        tap("tags.releaseProbe")
        var value = try waitSavedState("available")
        try assertSavedRows(value)
        tap("tags.redraw")
        tap("article.header.author")
        value = try waitSavedState("available")
        XCTAssertEqual(value.redraws, 1); XCTAssertEqual(value.authorTaps, 1)
        XCTAssertEqual(value.probes, 1); XCTAssertEqual(value.leaseID, lease)
        try evidence(value, before: false)

        tap("tags.failReload")
        value = try waitSavedState("failed")
        XCTAssertEqual(value.fetches, 1); XCTAssertEqual(value.writes, 0); XCTAssertEqual(value.probes, 2)
        XCTAssertEqual(try frame("status", in: value).width, try frame("container", in: value).width, accuracy: 0.5)
        let retry = app.buttons["offline.body.retry"]
        XCTAssertTrue(retry.exists); XCTAssertTrue(retry.isHittable)
        XCTAssertGreaterThanOrEqual(retry.frame.height + 0.001, 44)
        XCTAssertTrue(app.scrollViews["tags.scroll"].frame.insetBy(dx: -0.5, dy: -0.5).contains(retry.frame))
        try evidence(value, before: false)
        tap("offline.body.retry")
        value = try waitSavedState("pending")
        XCTAssertEqual(value.fetches, 2); XCTAssertEqual(value.writes, 0)
        XCTAssertEqual(value.leaseID, lease); XCTAssertEqual(value.probes, 2)
        try evidence(value, before: false)
        tap("tags.releaseBody")
        value = try waitSavedState("available")
        XCTAssertEqual(value.fetches, 2); XCTAssertEqual(value.writes, 1)
        XCTAssertEqual(value.probes, 2); XCTAssertEqual(value.leaseID, lease)
        XCTAssertEqual(value.prepareCalls, 1,
            "Presentation changes never remount the status task or force a checking cycle")
        try assertSavedRows(value)
        try evidence(value, before: false)
        XCTAssertEqual(app.staticTexts["tags.firebase"].label, "Firebase: ikke startet")
    }

}
