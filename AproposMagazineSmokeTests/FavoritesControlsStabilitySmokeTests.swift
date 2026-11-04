import UIKit
import XCTest

/// The actual Min side controls, rows and header at the owner's phone width.
/// Raw ViewThatFits geometry is retained separately from coherent snapshots;
/// screen/video review determines whether a transient was actually rendered.
final class FavoritesControlsStabilitySmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private var visibleAXSamples: [[String: Any]] = []
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposNotificationInboxSmoke", "-AproposFavoritesControlsStabilitySmoke", "-ResetFavoritesSortPreferenceSmoke"]
        if name.contains("ControlsStayOnOneRow") { app.launchArguments.append("-AproposFavoritesSortTitleAZSmoke") }
        if name.contains("RecentSaveOrder") { app.launchArguments.append("-AproposFavoritesSavedOrderSmoke") }
        app.launch()
        XCTAssertTrue(app.staticTexts["notifications.fixture.firebase"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["notifications.fixture.firebase"].label, "Firebase: ikke startet")
        checkpoint()
        wait("actual controls and first row have geometry") {
            guard let value = try? self.probe(),
                  let frames = value["layoutFrames"] as? [String: [String: Double]] else { return false }
            return ["container", "sort", "category", "search", "count", "firstRow"].allSatisfy { frames[$0] != nil }
        }
    }
    override func tearDownWithError() throws { app?.terminate(); app = nil }
    private func root() throws -> [String: Any] {
        let text = app.staticTexts["notifications.fixture.report"]
        let data = try XCTUnwrap(text.label.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func probe() throws -> [String: Any] { try XCTUnwrap(root()["controlsStability"] as? [String: Any]) }
    private func capture(_ phase: String) {
        let pixels = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        pixels.name = "Favorite controls stability — \(phase)"; pixels.lifetime = .keepAlways; add(pixels)
        if let value = try? root(), let bytes = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            let receipt = XCTAttachment(data: bytes, uniformTypeIdentifier: "public.json")
            receipt.name = "Favorite controls continuous geometry — \(phase)"; receipt.lifetime = .keepAlways; add(receipt)
        }
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Favorite controls AX — \(phase)"; tree.lifetime = .keepAlways; add(tree)
        let search = app.buttons["favorites.controls.search"]
        if app.buttons["minside.page.saved"].value as? String == "Valgt", search.exists && search.isHittable {
            func rect(_ value: CGRect) -> [String: Double] {
                ["x": Double(value.minX), "y": Double(value.minY), "width": Double(value.width), "height": Double(value.height)]
            }
            let count = app.staticTexts["4 artikler"].firstMatch
            if count.exists {
                let value: [String: Any] = ["phase": phase, "frames": [
                    "sort": rect(app.buttons["favorites.controls.sort"].frame),
                    "category": rect(app.buttons["favorites.controls.category"].frame),
                    "search": rect(search.frame), "count": rect(count.frame),
                    "firstRow": rect(app.buttons["notifications.fixture.favorite.saved-film"].frame)]]
                visibleAXSamples.append(value)
                if let bytes = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
                    let native = XCTAttachment(data: bytes, uniformTypeIdentifier: "public.json")
                    native.name = "Favorite controls actual native frames — \(phase)"; native.lifetime = .keepAlways; add(native)
                }
            }
        }
    }
    private func wait(_ phase: String, _ condition: @escaping () -> Bool) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        let result = XCTWaiter.wait(for: [expected], timeout: 8)
        if result != .completed { capture("failed wait " + phase) }
        XCTAssertEqual(result, .completed, phase)
    }
    private func advance(_ phase: String) {
        let button = app.buttons["favorites.controls.fixture.phase"]
        XCTAssertTrue(button.isHittable); button.tap()
        wait("fixture observation marker " + phase) {
            guard let value = try? self.probe() else { return false }
            return value["phase"] as? String == phase
        }
    }
    private func checkpoint() {
        let button = app.buttons["favorites.controls.fixture.checkpoint"]
        XCTAssertTrue(button.waitForExistence(timeout: 5) && button.isHittable); button.tap()
    }
    private func frame(_ key: String, in values: [String: [String: Double]]) throws -> CGRect {
        let value = try XCTUnwrap(values[key], key)
        return CGRect(x: try XCTUnwrap(value["x"]), y: try XCTUnwrap(value["y"]),
            width: try XCTUnwrap(value["width"]), height: try XCTUnwrap(value["height"]))
    }
    private func tapHeader(_ saved: Bool) throws {
        let button = app.buttons[saved ? "minside.page.saved" : "minside.page.messages"]
        let frames = try XCTUnwrap(root()["frames"] as? [String: [String: Double]])
        let visible = button.frame.intersection(try frame("minside.header", in: frames)).intersection(app.frame)
        XCTAssertGreaterThanOrEqual(visible.width, 43.5); XCTAssertGreaterThanOrEqual(visible.height, 44)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: visible.midX, dy: visible.midY)).tap()
        wait("actual title selection") { button.value as? String == "Valgt" }
    }

    func testControlsStayOnOneRowAcrossEntryMenusHeaderAndUnchangedRefresh() throws {
        XCTAssertEqual(app.frame.width, 402, accuracy: 1, "The owner's actual normal phone width")
        XCTAssertEqual(try root()["systemAccessibility"] as? Bool, false)
        XCTAssertEqual(try root()["systemTextCategory"] as? String, "UICTContentSizeCategoryL")
        XCTAssertEqual(try root()["favoriteIDs"] as? [String], ["saved-film", "saved-culture", "saved-music", "saved-fourth"])
        XCTAssertTrue(app.staticTexts["4 artikler"].exists)
        capture("startup with actual four saved articles, Titel A-Å and Alle")

        advance("sort-menu")
        app.buttons["favorites.controls.sort"].tap()
        capture("native sort menu open, selection unchanged")
        let az = app.buttons["favorites.controls.sort.option.Titel A-Å"]
        XCTAssertTrue(az.waitForExistence(timeout: 5)); az.tap()
        checkpoint()
        capture("native sort menu closed with the same selection")

        advance("category-menu")
        app.buttons["favorites.controls.category"].tap()
        capture("native category menu open, selection unchanged")
        let all = app.buttons["favorites.controls.category.option.Alle"]
        XCTAssertTrue(all.waitForExistence(timeout: 5)); all.tap()
        checkpoint()
        capture("native category menu closed with the same selection")

        advance("header-roundtrip")
        try tapHeader(false)
        capture("saved controls retained offscreen during actual messages selection")
        try tapHeader(true)
        checkpoint()
        capture("actual saved page returns with unchanged controls")

        advance("refresh")
        let refresh = app.buttons["favorites.controls.fixture.refresh"]
        XCTAssertTrue(refresh.isHittable); refresh.tap()
        wait("four genuine injected-model refreshes finished") {
            guard let value = try? self.probe() else { return false }
            return value["phase"] as? String == "refresh-complete" && value["refreshes"] as? Int == 4
        }
        let search = app.buttons["favorites.controls.search"]
        XCTAssertTrue(search.isHittable); search.tap()
        checkpoint()

        let report = try root(), value = try probe()
        // Preserve startup and every operation's raw callbacks before asserting
        // layout stability. No frame or size class has been forced.
        capture("all raw and coherent observations before layout assertions")
        XCTAssertEqual(value["rawDropped"] as? Int, 0)
        XCTAssertEqual(value["snapshotsDropped"] as? Int, 0)
        let raw = try XCTUnwrap(value["rawEvents"] as? [[String: Any]])
        XCTAssertFalse(raw.isEmpty)
        XCTAssertTrue(raw.contains { $0["key"] as? String == "search" })
        XCTAssertTrue(raw.contains { $0["key"] as? String == "count" })
        let snapshots = try XCTUnwrap(value["snapshots"] as? [[String: Any]])
        let signature = try XCTUnwrap(value["signature"] as? String)
        let eligible = snapshots.filter {
            $0["coherent"] as? Bool == true && $0["pageVisible"] as? Bool == true
                && $0["candidateQualified"] as? Bool == true
                && $0["signature"] as? String == signature
                && abs(($0["viewportWidth"] as? Double ?? 0) - 402) < 1
        }
        XCTAssertFalse(eligible.isEmpty, "Require coherent selected-page observations, not hidden candidate callbacks")
        var rowYs: [CGFloat] = []
        for snapshot in eligible {
            let frames = try XCTUnwrap(snapshot["frames"] as? [String: [String: Double]])
            let sort = try frame("sort", in: frames), category = try frame("category", in: frames)
            let search = try frame("search", in: frames), count = try frame("count", in: frames)
            XCTAssertEqual(search.midY, sort.midY, accuracy: 1, "Search stays beside the actual filters")
            XCTAssertEqual(count.midY, sort.midY, accuracy: 1, "Count stays beside the actual filters")
            XCTAssertEqual(category.midY, sort.midY, accuracy: 1)
            rowYs.append(try frame("firstRow", in: frames).minY)
        }
        XCTAssertLessThanOrEqual((rowYs.max() ?? 0) - (rowYs.min() ?? 0), 1, "The first actual article does not jump for unchanged control inputs")
        XCTAssertFalse(visibleAXSamples.isEmpty)
        var nativeRowYs: [CGFloat] = []
        for sample in visibleAXSamples {
            let frames = try XCTUnwrap(sample["frames"] as? [String: [String: Double]])
            let sort = try frame("sort", in: frames)
            XCTAssertEqual(try frame("search", in: frames).midY, sort.midY, accuracy: 1)
            XCTAssertEqual(try frame("count", in: frames).midY, sort.midY, accuracy: 1)
            nativeRowYs.append(try frame("firstRow", in: frames).minY)
        }
        XCTAssertLessThanOrEqual((nativeRowYs.max() ?? 0) - (nativeRowYs.min() ?? 0), 1,
            "Visible native AX positions cross-check selected-candidate geometry; video retains transient visibility")
        XCTAssertEqual(report["selectedCategory"] as? String, "Alle")
        XCTAssertEqual(report["selectedSort"] as? String, "Titel A-Å")
        XCTAssertEqual(report["favoriteIDs"] as? [String], ["saved-film", "saved-culture", "saved-music", "saved-fourth"])
        XCTAssertEqual(report["searchRequests"] as? Int, 1)
        XCTAssertEqual(report["firebaseStarted"] as? Bool, false)
        for id in ["sort", "category", "search"] {
            let action = app.buttons["favorites.controls." + id]
            XCTAssertTrue(action.exists && action.isHittable)
            XCTAssertGreaterThanOrEqual(action.frame.width, 44)
            XCTAssertGreaterThanOrEqual(action.frame.height, 44)
        }
    }

    func testNewestSelectionKeepsSearchAndCountOnNormalTextFilterRow() throws {
        XCTAssertEqual(app.frame.width, 402, accuracy: 1, "The owner's normal phone width")
        XCTAssertEqual(try root()["systemAccessibility"] as? Bool, false)
        XCTAssertEqual(try root()["systemTextCategory"] as? String, "UICTContentSizeCategoryL")
        let initialSearch = app.buttons["favorites.controls.search"].frame
        capture("before owner newest selection at normal text")
        app.buttons["favorites.controls.sort"].tap()
        let newest = app.buttons["favorites.controls.sort.option.Nyeste først"]
        XCTAssertTrue(newest.waitForExistence(timeout: 5))
        XCTAssertEqual(newest.label, "Nyeste udgivelser", "The existing raw sort ID now has an explicit publication label")
        newest.tap()
        wait("actual native menu selects newest") {
            (try? self.root()["selectedSort"] as? String) == "Nyeste først"
        }
        checkpoint()
        capture("after owner newest selection at normal text")
        let sort = app.buttons["favorites.controls.sort"].frame
        let category = app.buttons["favorites.controls.category"].frame
        let search = app.buttons["favorites.controls.search"].frame
        let count = app.staticTexts["4 artikler"].firstMatch
        XCTAssertTrue(count.exists)
        XCTAssertEqual(search.midY, sort.midY, accuracy: 1, "Selecting the longer sort label cannot move search to another row")
        XCTAssertEqual(count.frame.midY, sort.midY, accuracy: 1, "Count stays beside sort and category at normal text")
        XCTAssertEqual(category.midY, sort.midY, accuracy: 1)
        XCTAssertEqual(search.minY, initialSearch.minY, accuracy: 1, "The real search button does not jump when only sorting changes")
        XCTAssertEqual(try root()["firebaseStarted"] as? Bool, false)
    }

    func testInitialSortOffersRecentlySavedRatherThanTitleAsTheDefault() throws {
        capture("actual initial default sort before any user selection")
        XCTAssertEqual(try root()["selectedSort"] as? String, "Senest gemt",
            "An unset Min side preference should show most recently added membership first")
        XCTAssertEqual(app.buttons["favorites.controls.sort"].value as? String, "Senest gemt")
        XCTAssertEqual(try root()["firebaseStarted"] as? Bool, false)
    }


    func testRecentSaveOrderUsesActualSaveActionsAndRetainsExplicitSortAcrossColdLaunch() throws {
        wait("three actual saved actions have finished") {
            (try? self.root()["favoriteIDs"] as? [String]) == ["saved-culture", "saved-film", "saved-music"]
        }
        XCTAssertEqual(try root()["selectedSort"] as? String, "Senest gemt")
        let stamps = try XCTUnwrap(root()["savedAtByID"] as? [String: Double])
        XCTAssertEqual(stamps, ["saved-culture": 300, "saved-film": 200, "saved-music": 100])
        capture("actual save order differs from alphabetical and ID ordering")
        app.buttons["favorites.controls.sort"].tap()
        let title = app.buttons["favorites.controls.sort.option.Titel Å-A"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap()
        wait("explicit reverse-title preference saved") {
            (try? self.root()["storedSortPreference"] as? String) == "Titel Å-A"
        }
        app.terminate()
        app.launchArguments.removeAll { $0 == "-ResetFavoritesSortPreferenceSmoke" }
        app.launch()
        XCTAssertTrue(app.staticTexts["notifications.fixture.firebase"].waitForExistence(timeout: 10))
        wait("cold fixture reads the same explicit user preference") {
            (try? self.root()["selectedSort"] as? String) == "Titel Å-A"
        }
        XCTAssertEqual(app.buttons["favorites.controls.sort"].value as? String, "Titel Å-A")
        XCTAssertEqual(try root()["favoriteIDs"] as? [String], ["saved-music", "saved-culture", "saved-film"])
        XCTAssertEqual(try root()["firebaseStarted"] as? Bool, false)
        capture("cold launch respects an explicit title sort instead of forcing default")
    }

}
