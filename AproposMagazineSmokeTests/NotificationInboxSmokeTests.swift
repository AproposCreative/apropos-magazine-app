import XCTest
import UIKit

/// Shared production Min side pages, list and saved-row presentation. Destination
/// assertions are typed local navigation receipts, never real article/audio work.
final class NotificationInboxSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private var originalOrientation: UIDeviceOrientation = .unknown
    override func setUpWithError() throws {
        continueAfterFailure = false
        originalOrientation = XCUIDevice.shared.orientation
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposNotificationInboxSmoke"]
        if name.contains("PublicationCatchup") { app.launchArguments.append("-AproposNotificationPublicationCatchupSmoke") }
        if name.contains("PublicationCatchupEnglish") { app.launchArguments.append("-AproposNotificationPublicationEnglishSmoke") }
        if name.contains("Covers") { app.launchArguments.append("-AproposNotificationCoversSmoke") }
        if name.contains("Rejected") { app.launchArguments.append("-AproposNotificationRejectRouteSmoke") }
        if name.contains("LargestText") {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.staticTexts["notifications.fixture.firebase"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["notifications.fixture.firebase"].label, "Firebase: ikke startet")
        XCTAssertTrue(app.buttons["minside.page.saved"].waitForExistence(timeout: 5))
    }
    override func tearDownWithError() throws {
        app?.terminate(); app = nil
        XCUIDevice.shared.orientation = originalOrientation
    }

    private func capture(_ phase: String) {
        let screen = XCUIScreen.main.screenshot(), source = screen.image
        let shot: XCTAttachment
        if source.imageOrientation == .up { shot = XCTAttachment(screenshot: screen) }
        else {
            let format = UIGraphicsImageRendererFormat(); format.scale = source.scale
            let image = UIGraphicsImageRenderer(size: source.size, format: format).image { _ in
                source.draw(in: CGRect(origin: .zero, size: source.size))
            }
            shot = XCTAttachment(image: image)
        }
        shot.name = "Min side — \(phase)"; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Min side AX — \(phase)"; tree.lifetime = .keepAlways; add(tree)
        let reportElement = app.staticTexts["notifications.fixture.report"]
        if reportElement.exists, let report = reportElement.label.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: report)) != nil {
            let state = XCTAttachment(data: report, uniformTypeIdentifier: "public.json")
            state.name = "Min side callbacks — \(phase)"; state.lifetime = .keepAlways; add(state)
        }
    }
    private func report() throws -> [String: Any] {
        let value = app.staticTexts["notifications.fixture.report"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        let data = try XCTUnwrap(value.label.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func wait(_ phase: String, _ condition: @escaping () -> Bool) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        let result = XCTWaiter.wait(for: [expected], timeout: 8)
        if result != .completed { capture("failed wait: " + phase) }
        XCTAssertEqual(result, .completed, phase)
    }
    private func assertPage(_ title: String) {
        let id = title == "Min side" ? "minside.page.saved" : "minside.page.messages"
        wait("shared header " + title) { self.app.buttons[id].value as? String == "Valgt" }
        XCTAssertTrue(app.buttons["minside.settings"].isHittable)
        XCTAssertFalse(app.buttons["notifications.entry"].exists)
    }
    private func tapTitle(_ saved: Bool) throws {
        let button = app.buttons[saved ? "minside.page.saved" : "minside.page.messages"]
        let visible = button.frame.intersection(try frame("minside.header", state: report())).intersection(app.frame)
        XCTAssertGreaterThanOrEqual(visible.width, 43.5)
        XCTAssertGreaterThanOrEqual(visible.height, 44)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: visible.midX, dy: visible.midY)).tap()
    }
    private func openInbox() throws {
        assertPage("Min side")
        let entry = app.buttons["minside.page.messages"], settings = app.buttons["minside.settings"]
        for control in [entry, settings] {
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
        }
        XCTAssertEqual(entry.value as? String, "Ikke valgt")
        capture("shared Min side header and actual saved rows")
        try tapTitle(false)
        assertPage("Meddelelser")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "notifications.list").firstMatch.exists)
        for obsolete in ["notifications.options", "notifications.close", "notifications.openContent", "notifications.detail.close"] {
            XCTAssertFalse(app.buttons[obsolete].exists, obsolete)
        }
    }
    private func row(_ id: String, generic: Bool = false) -> XCUIElement {
        let identifier = (generic ? "notifications.message." : "notifications.item.") + id
        return app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    private var list: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "notifications.list").firstMatch
    }
    private func reveal(_ id: String, generic: Bool = false, upwards: Bool = true) {
        let item = row(id, generic: generic)
        for _ in 0..<16 {
            if item.exists && item.isHittable { return }
            if upwards { list.swipeUp(velocity: .slow) } else { list.swipeDown(velocity: .slow) }
        }
        capture("row not reachable \(id)")
        XCTAssertTrue(item.exists && item.isHittable)
    }
    private func frame(_ key: String, state: [String: Any]) throws -> CGRect {
        let frames = try XCTUnwrap(state["frames"] as? [String: [String: Double]])
        let value = try XCTUnwrap(frames[key], key)
        return CGRect(x: try XCTUnwrap(value["x"]), y: try XCTUnwrap(value["y"]),
                      width: try XCTUnwrap(value["width"]), height: try XCTUnwrap(value["height"]))
    }
    private func visibleTap(_ element: XCUIElement) {
        let visible = element.frame.intersection(app.frame)
        XCTAssertGreaterThan(visible.height, 0)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: visible.midX, dy: visible.midY)).tap()
    }
    private func pageSwipe(left: Bool, y: CGFloat) {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: app.frame.width * (left ? 0.84 : 0.16), dy: y))
        let end = origin.withOffset(CGVector(dx: app.frame.width * (left ? 0.16 : 0.84), dy: y))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    func testSharedHeaderDirectRoutesAndInlineGenericMessage() throws {
        try openInbox()
        for (id, target, type) in [("article-one", "fixture-article", "new_article"),
                                   ("audio-two", "fixture-audio", "new_podcast"),
                                   ("narration-four", "fixture-narration", "new_narration")] {
            reveal(id)
            let button = app.buttons["notifications.item.\(id)"]
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            button.tap()
            let destination = app.staticTexts["notifications.fixture.destination"]
            XCTAssertTrue(destination.waitForExistence(timeout: 5))
            XCTAssertEqual(destination.label, target)
            XCTAssertEqual(app.staticTexts["notifications.fixture.destination.type"].label, type)
            let path = try XCTUnwrap(report()["path"] as? [[String: String]])
            XCTAssertEqual(path, [["identifier": target, "type": type]])
            capture("direct \(type) native route receipt")
            app.buttons["notifications.fixture.route.back"].tap()
            assertPage("Meddelelser")
        }
        reveal("manual-three", generic: true)
        let generic = row("manual-three", generic: true)
        XCTAssertTrue(generic.label.contains("Der er ikke en ekstra side at åbne."))
        XCTAssertFalse(app.buttons["notifications.message.manual-three"].exists)
        XCTAssertFalse(app.buttons["notifications.item.manual-three"].exists)
        visibleTap(generic)
        assertPage("Meddelelser")
        let state = try report()
        XCTAssertEqual(state["opened"] as? [String], ["fixture-article", "fixture-audio", "fixture-narration"])
        XCTAssertEqual(state["openTypes"] as? [String], ["new_article", "new_podcast", "new_narration"])
        XCTAssertEqual((state["path"] as? [[String: String]])?.count, 0)
        XCTAssertEqual(state["firebaseStarted"] as? Bool, false)
        XCTAssertFalse(app.navigationBars["Meddelelse"].exists)
        capture("generic message stays inline without expansion")
    }

    func testHeaderTapsRetainSavedFiltersAndSettings() throws {
        assertPage("Min side")
        app.buttons["favorites.controls.category"].tap()
        let music = app.buttons["favorites.controls.category.option.Musik"]
        XCTAssertTrue(music.waitForExistence(timeout: 5)); music.tap()
        app.buttons["favorites.controls.sort"].tap()
        let reverse = app.buttons["favorites.controls.sort.option.Titel Å-A"]
        XCTAssertTrue(reverse.waitForExistence(timeout: 5)); reverse.tap()
        let favorite = app.buttons["notifications.fixture.favorite.saved-music"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 5) && favorite.isHittable)
        let before = try report()
        XCTAssertEqual(before["favoriteIDs"] as? [String], ["saved-music"])
        XCTAssertEqual(before["selectedCategory"] as? String, "Musik")
        XCTAssertEqual(before["selectedSort"] as? String, "Titel Å-A")
        let header = try frame("minside.header", state: before)
        capture("filtered actual saved row before shared title selection")
        try tapTitle(false)
        assertPage("Meddelelser")
        capture("actual title tap selects messages")
        XCTAssertEqual(try frame("minside.header", state: report()).minY, header.minY, accuracy: 1)
        let state = try report()
        XCTAssertEqual(state["removedFavoriteIDs"] as? [String], [])
        try tapTitle(true)
        assertPage("Min side")
        XCTAssertEqual(app.buttons["favorites.controls.category"].value as? String, "Musik")
        XCTAssertEqual(app.buttons["favorites.controls.sort"].value as? String, "Titel Å-A")
        XCTAssertTrue(favorite.isHittable)
        try tapTitle(false)
        assertPage("Meddelelser")
        app.buttons["minside.settings"].tap()
        XCTAssertTrue(app.staticTexts["notifications.fixture.settings"].waitForExistence(timeout: 5))
        capture("shared settings action local receipt")
        app.buttons["notifications.fixture.settings.close"].tap()
        assertPage("Meddelelser")
        try tapTitle(true)
        assertPage("Min side")
        let returned = try report()
        XCTAssertEqual(returned["settingsRequests"] as? Int, 1)
        XCTAssertEqual(returned["selectedCategory"] as? String, "Musik")
        XCTAssertEqual(returned["favoriteIDs"] as? [String], ["saved-music"])
        XCTAssertEqual(returned["firebaseStarted"] as? Bool, false)
        capture("saved filter and sort retained after paging and settings")
    }

    private func waitArtwork(_ id: String, url: String, phase: String) throws {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let state = try? self.report(),
                  let phases = state["artworkPhases"] as? [String: String] else { return false }
            guard phases["\(id).\(url)"] == phase else { return false }
            if phase == "loaded" {
                let frames = state["frames"] as? [String: [String: Double]]
                return frames?["cover.\(id).\(url)"]?["width"] == 56
            }
            return true
        }, object: nil)
        let result = XCTWaiter.wait(for: [expected], timeout: 10)
        if result != .completed { capture("artwork wait \(id) \(phase)") }
        XCTAssertEqual(result, .completed)
    }
    func testArticleCoversAlignRightAndMessagesStayTextOnly() throws {
        try openInbox()
        capture("cover inbox before row assertions")
        let warm = "https://covers.example.invalid/warm.png", cold = "https://covers.example.invalid/cold.png"
        for (id, url) in [("article-one", warm), ("narration-four", cold)] {
            reveal(id); try waitArtwork(id, url: url, phase: "loaded")
            let state = try report()
            XCTAssertEqual(state["firebaseStarted"] as? Bool, false)
            XCTAssertEqual(state["fixtureIssue"] as? String, "")
            let row = try frame("row.\(id)", state: state)
            let text = try frame("text.\(id)", state: state)
            let cover = try frame("cover.\(id).\(url)", state: state)
            XCTAssertEqual(cover.width, 56, accuracy: 0.5); XCTAssertEqual(cover.height, 72, accuracy: 0.5)
            XCTAssertLessThanOrEqual(text.maxX, cover.minX - 10)
            XCTAssertEqual(cover.maxX, row.maxX, accuracy: 1)
            XCTAssertEqual(text.minX, row.minX, accuracy: 1)
            capture("right aligned loaded cover \(id)")
        }
        for id in ["manual-three", "article-missing"] {
            reveal(id, generic: id == "manual-three")
            if id == "article-missing" {
                try waitArtwork(id, url: "https://covers.example.invalid/missing.png", phase: "failed")
            }
            let state = try report()
            let frames = try XCTUnwrap(state["frames"] as? [String: [String: Double]])
            XCTAssertFalse(frames.keys.contains { $0.hasPrefix("cover.\(id).") })
            let row = try frame("row.\(id)", state: state), text = try frame("text.\(id)", state: state)
            XCTAssertEqual(text.minX, row.minX, accuracy: 1)
            XCTAssertLessThan(row.maxX - text.maxX, 25, "No blank cover gutter")
            capture("text only \(id)")
        }
        try tapTitle(true)
        assertPage("Min side")
        let change = app.buttons["notifications.fixture.changeCover"]
        let favorites = app.descendants(matching: .any).matching(identifier: "notifications.fixture.favorites").firstMatch
        for _ in 0..<10 {
            if change.exists && change.isHittable { break }
            favorites.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(change.exists && change.isHittable); change.tap()
        try tapTitle(false)
        assertPage("Meddelelser")
        reveal("article-one", upwards: false)
        let alternate = "https://covers.example.invalid/alternate.png"
        try waitArtwork("article-one", url: alternate, phase: "loaded")
        _ = try frame("cover.article-one.\(alternate)", state: report())
        capture("same message with replaced cover URL")
    }

    func testRejectedTypedRouteKeepsMessagesAndShowsUnavailableAlert() throws {
        try openInbox()
        app.buttons["notifications.item.article-one"].tap()
        let alert = app.alerts["Indholdet kan ikke åbnes lige nu"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        capture("rejected typed route uses actual local alert")
        alert.buttons["OK"].tap()
        assertPage("Meddelelser")
        let state = try report()
        XCTAssertEqual(state["attempts"] as? [String], ["fixture-article"])
        XCTAssertEqual(state["opened"] as? [String], [])
        XCTAssertEqual((state["path"] as? [[String: String]])?.count, 0)
        XCTAssertFalse(app.staticTexts["notifications.fixture.destination"].exists)
        XCTAssertEqual(state["firebaseStarted"] as? Bool, false)
        capture("rejected route remains in the same messages page")
    }

    func testInlineGenericAtLargestTextAndIPadRotation() throws {
        try openInbox()
        XCTAssertEqual(try report()["systemAccessibility"] as? Bool, true)
        reveal("manual-three", generic: true)
        let state = try report()
        let body = try frame("body.manual-three", state: state)
        let lineHeight = try XCTUnwrap(state["bodyLineHeight"] as? Double)
        XCTAssertGreaterThan(body.height, CGFloat(lineHeight * 3), "Generic body has no three-line truncation")
        XCTAssertTrue(row("manual-three", generic: true).label.contains("Der er ikke en ekstra side at åbne."))
        for _ in 0..<16 {
            let current = try frame("body.manual-three", state: report())
            if current.maxY <= list.frame.maxY - 8 && current.maxY > list.frame.minY + 20 { break }
            list.swipeUp(velocity: .slow)
        }
        let end = try frame("body.manual-three", state: report())
        XCTAssertLessThanOrEqual(end.maxY, list.frame.maxY)
        XCTAssertGreaterThan(end.maxY, list.frame.minY + 20)
        capture("largest text generic ending remains inline and visibly reachable")
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            wait("actual iPad landscape") { self.app.frame.width > self.app.frame.height }
            assertPage("Meddelelser")
            capture("same shared pager after actual iPad landscape rotation")
            XCUIDevice.shared.orientation = .portrait
            wait("actual iPad portrait") { self.app.frame.height > self.app.frame.width }
            assertPage("Meddelelser")
            capture("same shared pager after return to portrait")
        }
        XCTAssertEqual((try report()["path"] as? [[String: String]])?.count, 0)
        XCTAssertEqual(try report()["firebaseStarted"] as? Bool, false)
    }

    private var publicationID: String { "article-publication:89abcdef0123456789abcdef" }
    private var englishPublicationID: String { "article-publication:en_89abcdef0123456789abcdef" }
    private func publicationState() throws -> [String: Any] {
        try XCTUnwrap(report()["publicationCatchup"] as? [String: Any])
    }
    private func assertLocalUnread(_ expected: Int) throws {
        wait("local unread model and badge spy both equal \(expected)") {
            guard let state = try? self.publicationState() else { return false }
            return state["unreadCount"] as? Int == expected && state["recordedBadgeValue"] as? Int == expected
        }
        XCTAssertEqual(try publicationState()["badgeEffectIsLocalSpyNotOSBadge"] as? Bool, true)
    }
    private func openPublicationPageAndFetch() throws {
        XCTAssertEqual(try publicationState()["deliveredPushCount"] as? Int, 0)
        XCTAssertEqual(try report()["count"] as? Int, 0)
        try tapTitle(false)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "notifications.empty").firstMatch.waitForExistence(timeout: 5))
        app.buttons["notifications.fixture.publication.refresh"].tap()
        wait("first fresh bilingual inventory is a silent baseline") {
            (try? self.publicationState()["freshPublicationLoads"] as? Int) == 1
        }
        XCTAssertEqual(try publicationState()["firstBaselineItemCount"] as? Int, 0)
        XCTAssertEqual(try publicationState()["confirmedFreshSourceCount"] as? Int, 2)
        XCTAssertEqual(try report()["count"] as? Int, 0)
        try assertLocalUnread(0)
        capture("fresh initial catalog stays silent without delivered push")
        app.buttons["notifications.fixture.publication.publish"].tap()
        wait("one later new typed article becomes one canonical message") {
            (try? self.report()["count"] as? Int) == 1
        }
        XCTAssertEqual(try publicationState()["confirmedFreshSourceCount"] as? Int, 3)
        XCTAssertEqual((try publicationState()["newlyPublishedIDs"] as? [String])?.count, 1)
        XCTAssertEqual(try publicationState()["deliveredPushCount"] as? Int, 0)
        XCTAssertEqual(try publicationState()["audioServiceOrRepositoryInjected"] as? Bool, false)
        try assertLocalUnread(1)
    }
    private func assertPublicationArticleRoute(_ id: String, target: String) throws {
        let button = app.buttons["notifications.item." + id]
        XCTAssertTrue(button.waitForExistence(timeout: 5) && button.isHittable)
        XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        button.tap()
        XCTAssertTrue(app.staticTexts["notifications.fixture.destination"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["notifications.fixture.destination"].label, target)
        XCTAssertEqual(app.staticTexts["notifications.fixture.destination.type"].label, "new_article")
        XCTAssertEqual(app.alerts.count, 0)
        try assertLocalUnread(0)
        capture("new publication opens article directly and is marked read without an audio resolver")
        app.buttons["notifications.fixture.route.back"].tap()
    }
    func testPublicationCatchupWithoutPushPersistsDeletesAndFiltersLanguage() throws {
        try openPublicationPageAndFetch()
        XCTAssertTrue(row(publicationID).exists)
        XCTAssertFalse(row(englishPublicationID).exists)
        try waitArtwork(publicationID, url: "https://covers.example.invalid/warm.png", phase: "loaded")
        let state = try report()
        let cover = try frame("cover.\(publicationID).https://covers.example.invalid/warm.png", state: state)
        XCTAssertEqual(cover.maxX, try frame("row.\(publicationID)", state: state).maxX, accuracy: 1)
        capture("genuine later article without push has its real right-hand cover")
        app.buttons["notifications.fixture.publication.coldReload"].tap()
        wait("cold model retains the one unread publication") {
            (try? self.publicationState()["coldModelReloads"] as? Int) == 1 && (try? self.report()["count"] as? Int) == 1
        }
        try assertLocalUnread(1)
        try assertPublicationArticleRoute(publicationID, target: "89abcdef0123456789abcdef")
        app.buttons["notifications.fixture.publication.refresh"].tap()
        XCTAssertEqual(try report()["count"] as? Int, 1, "Repeated fresh source cannot duplicate its canonical row")
        try assertLocalUnread(0)
        app.buttons["notifications.fixture.publication.language"].tap()
        XCTAssertEqual(try publicationState()["selectedLanguage"] as? String, "en")
        XCTAssertFalse(row(publicationID).exists)
        XCTAssertFalse(row(englishPublicationID).exists, "The English baseline must not be promoted into a message")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "notifications.empty").firstMatch.exists)
        app.buttons["notifications.fixture.publication.language"].tap()
        XCTAssertTrue(row(publicationID).waitForExistence(timeout: 5))
        let deleteFrame = row(publicationID).frame.intersection(app.frame)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: deleteFrame.minX + deleteFrame.width * 0.85, dy: deleteFrame.midY))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(
                dx: deleteFrame.minX + deleteFrame.width * 0.48, dy: deleteFrame.midY)),
                withVelocity: .slow, thenHoldForDuration: 0.15)
        let delete = app.buttons["notifications.delete." + publicationID]
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
        wait("canonical article dismissed") { !self.row(self.publicationID).exists }
        app.buttons["notifications.fixture.publication.refresh"].tap()
        app.buttons["notifications.fixture.publication.coldReload"].tap()
        wait("cold model retains dismissal instead of restoring catalog history") {
            (try? self.publicationState()["coldModelReloads"] as? Int) == 2 && (try? self.report()["count"] as? Int) == 0
        }
        app.buttons["notifications.fixture.publication.refresh"].tap()
        XCTAssertFalse(row(publicationID).exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "notifications.empty").firstMatch.exists)
        try assertLocalUnread(0)
        XCTAssertEqual(try report()["openTypes"] as? [String], ["new_article"])
        XCTAssertEqual(try report()["firebaseStarted"] as? Bool, false)
        capture("dismissed new article stays absent after refresh and a second cold model")
    }
    func testPublicationCatchupEnglishAtLargestText() throws {
        try openPublicationPageAndFetch()
        XCTAssertEqual(try report()["systemAccessibility"] as? Bool, true)
        XCTAssertEqual(try publicationState()["selectedLanguage"] as? String, "en")
        XCTAssertTrue(row(englishPublicationID).exists)
        XCTAssertFalse(row(publicationID).exists)
        try waitArtwork(englishPublicationID, url: "https://covers.example.invalid/cold.png", phase: "loaded")
        let state = try report()
        let cover = try frame("cover.\(englishPublicationID).https://covers.example.invalid/cold.png", state: state)
        let text = try frame("text.\(englishPublicationID)", state: state)
        XCTAssertLessThanOrEqual(text.maxX, cover.minX - 10)
        XCTAssertEqual(cover.width, 56, accuracy: 0.5)
        XCTAssertEqual(cover.height, 72, accuracy: 0.5)
        capture("new English publication after silent baseline at largest actual text size")
        try assertPublicationArticleRoute(englishPublicationID, target: "en_89abcdef0123456789abcdef")
        XCTAssertEqual(try report()["firebaseStarted"] as? Bool, false)
    }

}
