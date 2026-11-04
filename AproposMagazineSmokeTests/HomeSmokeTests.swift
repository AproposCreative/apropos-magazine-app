import CoreGraphics
import XCTest

/// Production Home, prepared rails and lists with the actual local cache and
/// preparation pipeline. Images, playback and navigation effects stay in memory.
final class HomeSmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate(); app = nil }

    private var status: XCUIElement { app.staticTexts["home.fixture.state"] }
    private func launch(_ scenario: String, reducedMotion: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposHomeSmoke", "-HomeSmokeScenario", scenario]
        if reducedMotion { app.launchArguments.append("-HomeSmokeReduceMotion") }
        if scenario == "podcastRows" {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", name.contains("LargestText")
                ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        }
        app.launch()
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        waitStatus(["firebase=off", "cache=1", "articles=19", "hero=5", "builds=1", "preparing=0"])
        if scenario == "listNavigation" {
            XCTAssertTrue(app.staticTexts["list.navigation.state"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Kultur"].waitForExistence(timeout: 5))
            return
        }
        let scroller: String
        switch scenario {
        case "authorAlignment": scroller = "home.fixture.authorAlignment"
        case "allCards": scroller = "home.fixture.allCards"
        case "compactRows": scroller = "home.fixture.compactRows"
        case "favoriteRows": scroller = "home.fixture.favoriteRows"
        case "favoriteControls": scroller = "home.fixture.favoriteControls"
        case "podcastRows": scroller = "home.podcast.list"
        default: scroller = "home.feed"
        }
        let container = scenario == "favoriteRows" || scenario == "favoriteControls"
            ? app.descendants(matching: .any).matching(identifier: scroller).firstMatch
            : app.scrollViews[scroller]
        XCTAssertTrue(container.waitForExistence(timeout: 5))
    }

    private func waitStatus(_ values: [String], file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: values.map {
            NSPredicate(format: "value CONTAINS %@", $0)
        })
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed, file: file, line: line)
    }
    private func metric(_ name: String, file: StaticString = #filePath, line: UInt = #line) -> Int {
        let value = status.value as? String ?? ""
        let token = value.split(separator: " ").first { $0.hasPrefix(name + "=") }
        let result = token.flatMap { Int($0.dropFirst(name.count + 1)) }
        XCTAssertNotNil(result, "Missing fixture metric: \(name)", file: file, line: line)
        return result ?? -1
    }

    @discardableResult
    private func reveal(_ item: XCUIElement, in identifier: String = "home.feed", fullyVisible: Bool = false,
                        topSegmentHeight: CGFloat? = nil,
                        file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let scroller = app.scrollViews[identifier]
        XCTAssertTrue(scroller.waitForExistence(timeout: 5), file: file, line: line)
        let appFrame = app.frame
        for _ in 0..<24 {
            let frame = scroller.frame.intersection(appFrame)
            let topInset: CGFloat = identifier == "home.feed" ? 72 : 12
            let bounds = CGRect(x: frame.minX + 12, y: frame.minY + topInset,
                width: max(1, frame.width - 24), height: max(1, frame.height - topInset - 16))
            var down = true
            var edgeDistance: CGFloat?
            if item.exists {
                let itemFrame = item.frame
                let target = topSegmentHeight.map {
                    CGRect(x: itemFrame.minX, y: itemFrame.minY, width: itemFrame.width, height: min($0, itemFrame.height))
                } ?? itemFrame
                if !target.isEmpty, target.midY.isFinite {
                    let center = CGPoint(x: target.midX, y: target.midY)
                    if bounds.contains(center), item.isHittable,
                       !fullyVisible || bounds.insetBy(dx: -1, dy: -1).contains(target) { return item }
                    down = target.midY >= bounds.midY
                    if fullyVisible {
                        if target.minY < bounds.minY { down = false; edgeDistance = bounds.minY - target.minY + 12 }
                        else if target.maxY > bounds.maxY { down = true; edgeDistance = target.maxY - bounds.maxY + 12 }
                    }
                }
            }
            let distance = min(min(380, bounds.height * 0.68), edgeDistance ?? .greatestFiniteMagnitude)
            let startY = down ? bounds.midY + distance / 2 : bounds.midY - distance / 2
            let endY = down ? bounds.midY - distance / 2 : bounds.midY + distance / 2
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: bounds.midX, dy: startY)).press(forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: bounds.midX, dy: endY)))
        }
        XCTFail("Home control outside the viewport: \(item.identifier)", file: file, line: line)
        return item
    }
    private func tap(_ item: XCUIElement, in scroller: String = "home.feed", file: StaticString = #filePath, line: UInt = #line) {
        reveal(item, in: scroller, file: file, line: line)
        XCTAssertTrue(item.isEnabled, file: file, line: line)
        XCTAssertTrue(item.isHittable, file: file, line: line)
        if name.contains("testPodcastRowsArtworkFillsTextHeight"),
           item.identifier == "home.podcast.play.audio-music" || item.identifier == "home.podcast.list.play.audio-music" {
            capturePodcastPreplayDiagnostics(item, scroller: scroller)
        }
        item.tap()
    }
    private func tapFixture(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let item = app.buttons[identifier]
        XCTAssertTrue(item.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(item.isEnabled, file: file, line: line)
        XCTAssertTrue(item.isHittable, file: file, line: line)
        item.tap()
    }
    private func waitAbsent(_ item: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == NO"), object: item)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }
    private func capture(_ title: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = title; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func assertDateContained(cardID: String, rail: String, file: StaticString = #filePath, line: UInt = #line) {
        let date = app.staticTexts[cardID + ".date"]
        reveal(date, fullyVisible: true, file: file, line: line)
        XCTAssertEqual(date.label, "21. september 2026", file: file, line: line)
        XCTAssertGreaterThan(date.frame.height, 0, file: file, line: line)
        let card = app.buttons[cardID], railView = app.scrollViews["home.rail.scroll." + rail]
        XCTAssertTrue(card.exists, file: file, line: line)
        XCTAssertTrue(railView.exists, file: file, line: line)
        XCTAssertTrue(card.frame.insetBy(dx: -1, dy: -1).contains(date.frame),
            "The whole date must be contained by the actual card", file: file, line: line)
        XCTAssertTrue(railView.frame.insetBy(dx: -1, dy: -1).contains(date.frame),
            "The whole date must be contained by the horizontal rail, not merely present in accessibility", file: file, line: line)
    }

    private func assertReadableAudioText(_ identifier: String, expected: String, card: XCUIElement,
                                         button: XCUIElement? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let text = app.staticTexts[identifier]
        reveal(text, fullyVisible: true, file: file, line: line)
        XCTAssertEqual(text.label, expected, file: file, line: line)
        XCTAssertGreaterThan(text.frame.height, 0, file: file, line: line)
        XCTAssertGreaterThan(text.frame.width, text.frame.height,
            "The short label must read across a line, not stack individual letters vertically", file: file, line: line)
        XCTAssertTrue(card.exists, file: file, line: line)
        XCTAssertTrue(card.frame.insetBy(dx: -1, dy: -1).contains(text.frame),
            "The full visible text must remain inside its actual audio card", file: file, line: line)
        if let button {
            XCTAssertTrue(button.frame.insetBy(dx: -1, dy: -1).contains(text.frame), file: file, line: line)
            XCTAssertTrue(card.frame.insetBy(dx: -1, dy: -1).contains(button.frame), file: file, line: line)
            XCTAssertTrue(button.isHittable, file: file, line: line)
        }
    }

    private func assertBottomAlignedAudioFooter(card: XCUIElement, category: XCUIElement,
                                               duration: XCUIElement? = nil, play: XCUIElement,
                                               playLabel: XCUIElement, pillPadding: CGFloat, contentInset: CGFloat = 12,
                                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(category.exists, file: file, line: line)
        XCTAssertTrue(playLabel.exists, file: file, line: line)
        // UIKit can report 43.99999999999997 for a 44 pt frame after scrolling.
        // Permit floating-point rounding only, not a visibly smaller target.
        XCTAssertGreaterThanOrEqual(play.frame.width + 0.001, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(play.frame.height + 0.001, 44, file: file, line: line)
        // Background cards expose their full padded frame. The transparent
        // Se alle row exposes only its content union, so its caller passes 0.
        let contentBottom = card.frame.maxY - contentInset
        XCTAssertEqual(category.frame.maxY, contentBottom, accuracy: 1,
            "Metadata must reach the artwork's bottom edge", file: file, line: line)
        if let duration {
            XCTAssertTrue(duration.exists, file: file, line: line)
            XCTAssertEqual(duration.frame.maxY, contentBottom, accuracy: 1, file: file, line: line)
        }
        XCTAssertEqual(playLabel.frame.maxY + pillPadding, contentBottom, accuracy: 1,
            "The visible capsule edge, not just its larger hit region, must align with the artwork", file: file, line: line)
        XCTAssertEqual(play.frame.maxY, contentBottom, accuracy: 1, file: file, line: line)
        XCTAssertTrue(card.frame.insetBy(dx: -1, dy: -1).contains(play.frame), file: file, line: line)
        let geometry = XCTAttachment(string: "\(card.identifier): accessibilityBottom=\(card.frame.maxY), insetWithinAXFrame=\(contentInset), contentBottom=\(contentBottom), categoryBottom=\(category.frame.maxY), pillBottom=\(playLabel.frame.maxY + pillPadding), hitBottom=\(play.frame.maxY)")
        geometry.name = "Visible footer alignment"; geometry.lifetime = .keepAlways; add(geometry)
    }

    func testMeasuredRailDefersOffscreenCoverUntilHorizontalEntryAndKeepsItAdmittedOnReturn() {
        launch("cache")
        let first = app.buttons["home.card.music.music-1"]
        reveal(first, fullyVisible: true, topSegmentHeight: 310)
        let rail = app.scrollViews["home.rail.scroll.music"]
        let last = app.buttons["home.card.music.music-6"]
        XCTAssertTrue(last.exists, "All card text participates in natural-height measurement")
        XCTAssertGreaterThanOrEqual(last.frame.minX, rail.frame.maxX)
        waitStatus(["firstCover=ready", "lastCover=blocked"])

        func swipe(left: Bool) {
            let visible = rail.frame.intersection(app.frame)
            let y = first.frame.minY + 155
            let fromX = visible.minX + visible.width * (left ? 0.85 : 0.15)
            let toX = visible.minX + visible.width * (left ? 0.15 : 0.85)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: fromX, dy: y)).press(forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: toX, dy: y)))
        }
        for _ in 0..<8 {
            if last.frame.minX >= rail.frame.minX - 1, last.frame.maxX <= rail.frame.maxX + 1 { break }
            swipe(left: true)
        }
        XCTAssertGreaterThanOrEqual(last.frame.minX, rail.frame.minX - 1)
        XCTAssertLessThanOrEqual(last.frame.maxX, rail.frame.maxX + 1)
        waitStatus(["lastCover=ready", "lastCoverEvents=blocked,ready"])
        capture("Home — sidste cover tillades først efter horisontalt swipe")

        for _ in 0..<8 {
            if first.frame.minX >= rail.frame.minX - 1, first.frame.maxX <= rail.frame.maxX + 1 { break }
            swipe(left: false)
        }
        XCTAssertGreaterThanOrEqual(first.frame.minX, rail.frame.minX - 1)
        XCTAssertLessThanOrEqual(first.frame.maxX, rail.frame.maxX + 1)
        XCTAssertGreaterThanOrEqual(last.frame.minX, rail.frame.maxX)
        let events = (status.value as? String ?? "").split(separator: " ").first { $0.hasPrefix("lastCoverEvents=") }.map(String.init)
        XCTAssertEqual(events, "lastCoverEvents=blocked,ready", "Leaving the viewport must not reset the cover's admission")
        waitStatus(["firstCover=ready", "lastCover=ready", "firebase=off", "builds=1", "opened=0", "played=0"])
    }

    func testLongEditorialCardsContainDateRatingAndWrappedTopicAtTheCurrentTextSize() {
        launch("layout")
        assertDateContained(cardID: "home.card.recommended.music-1", rail: "recommended")
        XCTAssertEqual(app.buttons["home.card.recommended.music-1"].frame.width, 173, accuracy: 1)
        capture("Home — lang kompakt korttekst og hel dansk dato")

        let cardID = "home.card.music.music-1"
        let category = app.staticTexts[cardID + ".category"]
        reveal(category, fullyVisible: true)
        let card = app.buttons[cardID]
        XCTAssertEqual(card.frame.width, 270, accuracy: 1)
        XCTAssertTrue(category.label.localizedCaseInsensitiveContains("internationale perspektiver"))
        XCTAssertGreaterThanOrEqual(category.frame.minX, card.frame.minX - 1)
        XCTAssertLessThanOrEqual(category.frame.maxX, card.frame.maxX + 1,
            "Long categories must wrap inside the existing card width")
        capture("Home — langt emne og skaleret titel inden for kortbredden")

        assertDateContained(cardID: cardID, rail: "music")
        let rating = app.descendants(matching: .any).matching(identifier: cardID + ".rating").firstMatch
        XCTAssertTrue(rating.exists)
        XCTAssertEqual(rating.label, "5 ud af 6 stjerner")
        let intro = app.staticTexts[cardID + ".intro"], date = app.staticTexts[cardID + ".date"]
        XCTAssertTrue(intro.exists)
        XCTAssertGreaterThanOrEqual(rating.frame.minY, intro.frame.maxY - 1)
        XCTAssertGreaterThanOrEqual(date.frame.minY, rating.frame.maxY - 1)
        capture("Home — lang indledning, rating og dato uden lodret klip")
        waitStatus(["firebase=off", "builds=1", "preparing=0"])
    }

    /// Compact geometry is asserted at the normal test text size. The separate
    /// listening test also runs at accessibility sizes, where cards must grow.
    func testNormalSizeAudioCardIsCompactWithoutAIBadgeAndKeepsSeparateActions() {
        launch("owner")
        let card = app.otherElements["home.podcast.card.audio-hero"]
        reveal(card, fullyVisible: true)
        let geometry = XCTAttachment(string: "Home audio card height: \(card.frame.height) pt; artwork 92 pt; vertical padding 12 + 12 pt")
        geometry.name = "Compact audio card geometry"; geometry.lifetime = .keepAlways; add(geometry)
        XCTAssertGreaterThan(card.frame.height, 0)
        XCTAssertLessThanOrEqual(card.frame.height, 117,
            "The normal card should fit 92 pt artwork plus 12 pt padding on each side")

        let title = app.buttons["home.podcast.open.hero-1"]
        XCTAssertTrue(title.exists)
        XCTAssertEqual(title.label, "Åbn artikel: Klubkultur og mode: Hvem får lov?")
        XCTAssertGreaterThan(title.frame.height, 0)
        XCTAssertTrue(card.frame.insetBy(dx: -1, dy: -1).contains(title.frame),
            "The complete title button must remain inside the actual compact card")
        let disclosure = card.descendants(matching: .any).matching(NSPredicate(
            format: "label IN %@", ["Oplæst med AI", "Oplæst med kunstig intelligens"]
        )).firstMatch
        XCTAssertFalse(disclosure.exists, "The Home card must not show an AI badge even for an actual AI-narration episode")

        let play = app.buttons["home.podcast.play.audio-hero"]
        XCTAssertGreaterThanOrEqual(play.frame.width + 0.001, 44)
        XCTAssertGreaterThanOrEqual(play.frame.height + 0.001, 44)
        XCTAssertLessThanOrEqual(title.frame.maxY, play.frame.minY + 1,
            "The title and playback action must not overlap")
        assertReadableAudioText("home.podcast.duration.audio-hero", expected: "10 min", card: card)
        assertReadableAudioText("home.podcast.playLabel.audio-hero", expected: "Lyt", card: card, button: play)
        assertBottomAlignedAudioFooter(card: card, category: app.staticTexts["home.podcast.category.audio-hero"],
            duration: app.staticTexts["home.podcast.duration.audio-hero"], play: play,
            playLabel: app.staticTexts["home.podcast.playLabel.audio-hero"], pillPadding: 6)
        capture("Home — kompakt lydkort med redaktionel titel og uden AI-mærke")
        play.tap()
        waitStatus(["played=1", "opened=0", "firebase=off", "builds=1"])

        tap(title)
        let opened = app.staticTexts["home.fixture.openedArticle"]
        XCTAssertTrue(opened.waitForExistence(timeout: 5))
        XCTAssertEqual(opened.label, "Fra redaktionen 1", "The title opens the bound article, not the player")
        waitStatus(["played=1", "opened=1", "firebase=off", "builds=1"])
    }

    func testNormalSizeResumeAndPodcastListFootersAlignAndKeepSeparateActions() {
        launch("owner")
        tapFixture("home.fixture.position")
        let resume = app.buttons["home.resume.play"], resumeCard = app.otherElements["home.resume.card"]
        reveal(resumeCard, fullyVisible: true)
        assertReadableAudioText("home.resume.playLabel", expected: "Fortsæt", card: resumeCard, button: resume)
        XCTAssertEqual(app.staticTexts["home.resume.category"].label, "Podcast")
        assertBottomAlignedAudioFooter(card: resumeCard, category: app.staticTexts["home.resume.category"],
            play: resume, playLabel: app.staticTexts["home.resume.playLabel"], pillPadding: 8)
        capture("Home — Podcast og synlig Fortsæt-pille flugter med coverets bund")
        resume.tap()
        waitStatus(["played=1", "opened=0"])

        tap(app.buttons["home.seeAll.podcasts"])
        let row = app.otherElements["home.podcast.list.row.audio-hero"]
        reveal(row, in: "home.podcast.list", fullyVisible: true)
        let play = app.buttons["home.podcast.list.play.audio-hero"]
        XCTAssertEqual(app.staticTexts["home.podcast.list.category.audio-hero"].label, "Kultur")
        XCTAssertEqual(app.staticTexts["home.podcast.list.playLabel.audio-hero"].label, "Lyt")
        assertBottomAlignedAudioFooter(card: row, category: app.staticTexts["home.podcast.list.category.audio-hero"],
            play: play, playLabel: app.staticTexts["home.podcast.list.playLabel.audio-hero"], pillPadding: 6, contentInset: 0)
        capture("Lydindhold Se alle — metadata og synlig Lyt-pille flugter med coverets bund")
        play.tap()
        waitStatus(["played=2", "opened=0", "firebase=off"])
        tap(app.buttons["home.podcast.list.article.hero-1"], in: "home.podcast.list")
        let opened = app.staticTexts["home.fixture.openedArticle"]
        XCTAssertTrue(opened.waitForExistence(timeout: 5))
        XCTAssertEqual(opened.label, "Fra redaktionen 1")
        waitStatus(["played=2", "opened=1", "firebase=off"])
    }

    func testPodcastListKeepsReadableMetadataAndSeparateActionsAtTheCurrentTextSize() {
        launch("owner")
        tap(app.buttons["home.seeAll.podcasts"])
        let row = app.otherElements["home.podcast.list.row.audio-hero"]
        let category = app.staticTexts["home.podcast.list.category.audio-hero"]
        reveal(category, in: "home.podcast.list", fullyVisible: true)
        XCTAssertEqual(category.label, "Kultur")
        XCTAssertTrue(row.frame.insetBy(dx: -1, dy: -1).contains(category.frame))
        let label = app.staticTexts["home.podcast.list.playLabel.audio-hero"]
        reveal(label, in: "home.podcast.list", fullyVisible: true)
        XCTAssertEqual(label.label, "Lyt")
        let play = app.buttons["home.podcast.list.play.audio-hero"]
        XCTAssertGreaterThanOrEqual(play.frame.width + 0.001, 44)
        XCTAssertGreaterThanOrEqual(play.frame.height + 0.001, 44)
        XCTAssertGreaterThan(label.frame.width, label.frame.height)
        XCTAssertTrue(play.frame.insetBy(dx: -1, dy: -1).contains(label.frame))
        XCTAssertTrue(row.frame.insetBy(dx: -1, dy: -1).contains(play.frame))
        capture("Lydindhold Se alle — læsbar tekst og fuld trykflade ved valgt tekststørrelse")
        play.tap()
        waitStatus(["played=1", "opened=0", "firebase=off"])
        tap(app.buttons["home.podcast.list.article.hero-1"], in: "home.podcast.list")
        XCTAssertTrue(app.staticTexts["home.fixture.openedArticle"].waitForExistence(timeout: 5))
        waitStatus(["played=1", "opened=1", "firebase=off"])
    }

    func testPodcastRowsArtworkFillsTextHeightAndKeepsSeparateActions() {
        assertPodcastRowsArtwork(accessibility: false)
    }

    func testPodcastRowsArtworkFillsTextHeightAtLargestTextAndKeepsSeparateActions() {
        assertPodcastRowsArtwork(accessibility: true)
    }

    func testPodcastArtworkRetainsSeparateArticleTouchTargets() {
        launch("podcastRows")
        for mode in ["list", "card"] {
            if mode == "card" { tapFixture("home.podcast.fixture.showCards") }
            let report = podcastRowsReport(mode: mode)
            let image = compactFrame(mode + ".audio-music.image", report: report)
            let scroller = app.scrollViews[mode == "list" ? "home.podcast.list" : "home.podcast.fixture.cards"]
            XCTAssertTrue(scroller.waitForExistence(timeout: 5))
            XCTAssertTrue(scroller.frame.intersection(app.frame).insetBy(dx: -1, dy: -1).contains(image),
                "Tap the visible measured artwork rather than an intrinsic accessibility image frame")
            attachPodcastRowsReport(report, title: "Lydrækker — \(mode), faktisk cover-trykflade")
            let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screen.name = "Lydrækker — \(mode), originalt skærmbillede før covertryk"
            screen.lifetime = .keepAlways; add(screen)
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: image.midX, dy: image.midY)).tap()
            let destination = app.staticTexts["home.podcast.fixture.destination"]
            XCTAssertTrue(destination.waitForExistence(timeout: 5))
            XCTAssertEqual(destination.label, "Musikkens nye stemmer 1")
            waitStatus(["played=0", "opened=1", "denied=0", "firebase=off"])
            tapFixture("home.podcast.fixture.return")
            waitStatus(["played=0", "opened=0", "denied=0"])
        }
    }

    /// The measured frames are attached after each real image clip and around
    /// the actual content, not inferred from an accessibility union. Gather
    /// both surfaces/actions before reporting decorative-layout failures.
    private func assertPodcastRowsArtwork(accessibility: Bool) {
        launch("podcastRows")
        var failures: [String] = []
        var expectedPlays = 0
        for mode in ["list", "card"] {
            if mode == "card" { tapFixture("home.podcast.fixture.showCards") }
            let scroller = mode == "list" ? "home.podcast.list" : "home.podcast.fixture.cards"
            let report = podcastRowsReport(mode: mode)
            XCTAssertEqual(report["systemTextCategory"] as? String, accessibility
                ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL")
            XCTAssertEqual(report["systemAccessibility"] as? Bool, accessibility)
            XCTAssertEqual(report["environmentAccessibility"] as? Bool, accessibility)
            XCTAssertEqual(report["firebaseStarted"] as? Bool, false)
            XCTAssertEqual(report["realPlayerStarted"] as? Bool, false)
            XCTAssertEqual(report["realReaderOpened"] as? Bool, false)
            XCTAssertEqual(report["remoteImagePolicy"] as? Bool, false)
            let titles = report["episodeTitles"] as? [String: String] ?? [:]
            XCTAssertGreaterThan(titles["audio-hero"]?.count ?? 0, 150,
                "The rendered episode title, rather than only Article.name, must be genuinely long")
            XCTAssertEqual(titles["audio-music"], "Musik")
            XCTAssertEqual(report["fixtureArtworkIDs"] as? [String], ["audio-music", "audio-hero"])
            XCTAssertEqual(report["placeholderIDs"] as? [String], ["audio-pending"])

            for id in ["audio-music", "audio-hero", "audio-pending"] {
                let prefix = mode + "." + id
                let content = compactFrame(prefix + ".content", report: report)
                let image = compactFrame(prefix + ".image", report: report)
                let text = compactFrame(prefix + ".text", report: report)
                let play = compactFrame(prefix + ".play", report: report)
                let label = compactFrame(prefix + ".artworkLabel", report: report)
                if abs(label.minX - image.minX) > 0.5 || abs(label.width - image.width) > 0.5
                    || abs(label.minY - image.minY) > 0.5 || abs(label.maxY - image.maxY) > 0.5 {
                    failures.append(prefix + ": the actual Button label must match the finite visible artwork frame; label=\(label), image=\(image)")
                }
                if label.intersects(play) {
                    failures.append(prefix + ": the actual artwork Button label must not overlap playback")
                }
                if abs(image.minY - content.minY) > 0.5 || abs(image.maxY - content.maxY) > 0.5 {
                    failures.append(prefix + ": artwork must span actual content top and bottom; image=\(image), content=\(content)")
                }
                if !content.insetBy(dx: -0.5, dy: -0.5).contains(image)
                    || !content.insetBy(dx: -0.5, dy: -0.5).contains(text)
                    || !content.insetBy(dx: -0.5, dy: -0.5).contains(play) {
                    failures.append(prefix + ": actual artwork, text and play target must remain inside the content")
                }
                if image.maxX > text.minX - 8 {
                    failures.append(prefix + ": artwork must retain a leading column and a readable text gap")
                }
                if play.width < 43.99 || play.height < 43.99 || image.intersects(play) {
                    failures.append(prefix + ": playback needs a separate non-overlapping 44pt target")
                }
            }
            if mode == "list" {
                XCTAssertGreaterThan(compactFrame("list.audio-hero.text", report: report).height, 64,
                    "The long-title fixture must actually exceed the former square thumbnail height")
            }
            attachPodcastRowsReport(report, title: "Lydrækker — \(mode), \(accessibility ? "AX5" : "normal")")
            capture("Lydrækker — \(mode), kort og begyndelsen på den lange titel, \(accessibility ? "AX5" : "normal")")

            let pendingID = mode == "list" ? "home.podcast.list.play.audio-pending" : "home.podcast.play.audio-pending"
            XCTAssertTrue(app.buttons[pendingID].exists)
            XCTAssertFalse(app.buttons[pendingID].isEnabled, "A placeholder/pending episode must not become playable")
            let pendingCategory = mode == "list" ? "home.podcast.list.category.audio-pending" : "home.podcast.category.audio-pending"
            reveal(app.staticTexts[pendingCategory], in: scroller, fullyVisible: true)
            attachPodcastRowsReport(podcastRowsReport(mode: mode), title: "Lydrækker — \(mode), placeholder og afventende episode")
            capture("Lydrækker — \(mode), placeholder, \(accessibility ? "AX5" : "normal")")
            let playID = mode == "list" ? "home.podcast.list.play.audio-music" : "home.podcast.play.audio-music"
            tap(app.buttons[playID], in: scroller)
            expectedPlays += 1
            waitStatus(["played=\(expectedPlays)", "opened=0", "denied=0", "firebase=off"])
            let articleID = mode == "list" ? "home.podcast.list.article.music-1" : "home.podcast.open.music-1"
            tap(app.buttons[articleID], in: scroller)
            let destination = app.staticTexts["home.podcast.fixture.destination"]
            XCTAssertTrue(destination.waitForExistence(timeout: 5))
            XCTAssertEqual(destination.label, "Musikkens nye stemmer 1")
            waitStatus(["played=\(expectedPlays)", "opened=1", "denied=0"])
            tapFixture("home.podcast.fixture.return")
            waitStatus(["played=\(expectedPlays)", "opened=0", "denied=0"])
            _ = podcastRowsReport(mode: mode)
        }
        let result = XCTAttachment(string: failures.isEmpty ? "All actual artwork/content and target checks passed" : failures.joined(separator: "\n"))
        result.name = "Actual audio-row artwork geometry checks"; result.lifetime = .keepAlways; add(result)
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    private func podcastRowsReport(mode: String) -> [String: Any] {
        let element = app.staticTexts["home.podcast.fixture.geometry"]
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let required = ["audio-music", "audio-hero", "audio-pending"].flatMap { id in
            ["content", "image", "text", "play", "artworkLabel"].map { mode + "." + id + "." + $0 }
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let raw = element.value as? String,
                  let value = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
                  value["mode"] as? String == mode,
                  let frames = value["frames"] as? [String: [String: Double]] else { return false }
            return required.allSatisfy { key in
                guard let frame = frames[key] else { return false }
                return (frame["width"] ?? 0) > 0 && (frame["height"] ?? 0) > 0
            }
        }, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
        let raw = element.value as? String ?? "{}"
        return (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] ?? [:]
    }

    /// Reads only: no new wait, scroll, second tap or callback expectation.
    /// The raw values deliberately do not claim that the scroll is stationary.
    private func capturePodcastPreplayDiagnostics(_ play: XCUIElement, scroller: String) {
        let raw = app.staticTexts["home.podcast.fixture.geometry"].value as? String ?? "{}"
        let geometry = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] ?? [:]
        let frame = play.frame, viewport = app.scrollViews[scroller].frame
        let payload: [String: Any] = [
            "observedAtUnix": Date().timeIntervalSince1970,
            "playIdentifier": play.identifier, "scrollerIdentifier": scroller,
            "fullFixtureStatus": status.value as? String ?? "",
            "rawGeometryReport": geometry,
            "queriedPlayAXFrame": ["x": Double(frame.minX), "y": Double(frame.minY),
                "width": Double(frame.width), "height": Double(frame.height)],
            "queriedScrollAXFrame": ["x": Double(viewport.minX), "y": Double(viewport.minY),
                "width": Double(viewport.width), "height": Double(viewport.height)],
            "scrollStationaryOrHitDeliveryProven": false
        ]
        attachPodcastRowsReport(payload, title: "Lydrækker — faktisk pre-play efter reveal, " + scroller)
        let original = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        original.name = "Lydrækker — original XCUIScreen umiddelbart før play, " + scroller
        original.lifetime = .keepAlways; add(original)
    }

    private func attachPodcastRowsReport(_ report: [String: Any], title: String) {
        let data = (try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])) ?? Data()
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = title + " — actual frames"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testAuthorCardsShowRatingsAndFillTheEntireCardHeight() {
        launch("authorAlignment")
        assertAuthorCards()
    }

    func testAuthorCardsPreserveFullHeightAndRatingsAcrossIPadRotation() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        launch("authorAlignment")
        assertAuthorCards()
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            guard let frame = self?.app.frame else { return false }
            return frame.width > frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 8), .completed)
        assertAuthorCards()
    }

    private func assertAuthorCards() {
        for sample in [("author-alignment", 5), ("author-no-intro", 0), ("author-six", 6), ("author-zero", 0)] {
            let id = sample.0
            let identifier = id == "author-alignment" ? "home.fixture.authorCard" :
                id == "author-no-intro" ? "home.fixture.authorCard.noIntro" : "home.fixture.authorCard." + id
            let row = reveal(app.otherElements[identifier], in: "home.fixture.authorAlignment", fullyVisible: true)
            XCTAssertTrue(row.exists)
            let reportElement = app.staticTexts["home.author.geometry"]
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard let value = reportElement.value as? String, let data = value.data(using: .utf8),
                      let report = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let frames = report["frames"] as? [String: [String: Double]] else { return false }
                guard let card = frames[id + ".card"], frames[id + ".image"] != nil,
                      let width = card["width"] else { return false }
                return abs(width - row.frame.width) < 1
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
            let value = reportElement.value as? String ?? "{}"
            let report = (try? JSONSerialization.jsonObject(with: Data(value.utf8))) as? [String: Any] ?? [:]
            let image = compactFrame(id + ".image", report: report)
            let card = compactFrame(id + ".card", report: report)
            let json = XCTAttachment(string: value); json.name = "Author card geometry — " + id
            json.lifetime = .keepAlways; add(json)
            let picture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            picture.name = "Author card full screen — " + id; picture.lifetime = .keepAlways; add(picture)
            XCTAssertEqual(image.width, 92, accuracy: 0.5)
            XCTAssertEqual(image.minX, card.minX, accuracy: 0.5)
            XCTAssertEqual(image.minY, card.minY, accuracy: 0.5)
            XCTAssertEqual(image.maxY, card.maxY, accuracy: 0.5)
            let title = compactFrame(id + ".title", report: report)
            let category = compactFrame(id + ".category", report: report)
            XCTAssertEqual(title.minX - image.maxX, 14, accuracy: 0.5)
            XCTAssertTrue(card.insetBy(dx: -0.5, dy: -0.5).contains(title))
            XCTAssertTrue(card.insetBy(dx: -0.5, dy: -0.5).contains(category))
            XCTAssertGreaterThan(title.height, 0)
            let rating = row.otherElements["author.article.rating." + id]
            if sample.1 > 0 {
                XCTAssertTrue(rating.exists)
                XCTAssertEqual(rating.label, "\(sample.1) ud af 6 stjerner")
                let stars = compactFrame(id + ".rating", report: report)
                XCTAssertTrue(card.insetBy(dx: -0.5, dy: -0.5).contains(stars))
                XCTAssertGreaterThanOrEqual(stars.minY, title.maxY)
            } else {
                XCTAssertFalse(rating.exists)
                let frames = report["frames"] as? [String: [String: Double]]
                XCTAssertNil(frames?[id + ".rating"])
            }
            XCTAssertEqual(report["firebaseStarted"] as? Bool, false)
        }
        waitStatus(["firebase=off", "opened=0", "played=0"])
    }

    func testNormalSizeAuthorCardKeepsLongEditorialTextAtTheArtworkBottom() {
        launch("authorAlignment")
        let card = app.otherElements["home.fixture.authorCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let intro = app.staticTexts["Mød menneskene bag historierne, og kom tættere på de idéer, der former vores hverdag."]
        XCTAssertTrue(intro.exists)
        XCTAssertGreaterThan(intro.frame.height, 0)
        XCTAssertTrue(card.frame.insetBy(dx: -1, dy: -1).contains(intro.frame))
        XCTAssertEqual(intro.frame.maxY, card.frame.maxY - 12, accuracy: 1)
        capture("Forfatterkort — lang redaktionel tekst og cover ved samme nederste kant")
        let emptyIntroCard = app.otherElements["home.fixture.authorCard.noIntro"]
        reveal(emptyIntroCard, in: "home.fixture.authorAlignment", fullyVisible: true)
        let lastTitle = emptyIntroCard.staticTexts["En kort historie uden indledning"]
        XCTAssertTrue(lastTitle.exists)
        XCTAssertTrue(emptyIntroCard.frame.insetBy(dx: -1, dy: -1).contains(lastTitle.frame))
        XCTAssertEqual(lastTitle.frame.maxY, emptyIntroCard.frame.maxY - 12, accuracy: 1,
            "An absent introduction must not leave a trailing spacer under the last title")
        capture("Forfatterkort — sidste titel flugter også uden indledning")
        waitStatus(["firebase=off", "opened=0", "played=0"])
    }

    func testAllArticleRowsAlignTheirLastTextAtTheContentBottomAtTheCurrentTextSize() {
        launch("allCards")
        // The transparent compact/Home rows expose content-only AX bounds;
        // their SwiftUI padding is outside that accessibility frame. The
        // category card's drawn background includes its actual 16 pt inset.
        let rows: [(kind: String, footer: String, insetWithinAXFrame: CGFloat)] = [
            ("favorite", "En gemt historie om kulturen og de mennesker, der giver den liv.", 0),
            ("compact", "Kultur og scenekunst", 0),
            ("categoryList", "Signe Jensen", 16),
            ("series", "Mød en ny generation af fortællere, som udfordrer vores blik på verden.", 0),
            ("homeList", "Generelt", 0)
        ]
        for value in rows {
            let row = app.otherElements["home.fixture.row." + value.kind]
            reveal(row, in: "home.fixture.allCards", fullyVisible: true)
            let footer = row.staticTexts.matching(NSPredicate(format: "label =[c] %@", value.footer)).firstMatch
            XCTAssertTrue(footer.exists, "The actual \(value.kind) row must expose its last editorial text")
            XCTAssertGreaterThan(footer.frame.height, 0)
            XCTAssertTrue(row.frame.insetBy(dx: -1, dy: -1).contains(footer.frame))
            XCTAssertEqual(footer.frame.maxY, row.frame.maxY - value.insetWithinAXFrame, accuracy: 1,
                "The last text in \(value.kind) must reach the row's content bottom")
            let geometry = XCTAttachment(string: "\(value.kind): accessibilityBottom=\(row.frame.maxY), insetWithinAXFrame=\(value.insetWithinAXFrame), footerBottom=\(footer.frame.maxY)")
            geometry.name = "Article row alignment — " + value.kind
            geometry.lifetime = .keepAlways
            add(geometry)
            // Decorative artwork remains outside accessibility. The captured
            // native row provides the complementary visual image-edge check.
            capture("Artikelkort — " + value.kind + " ved valgt tekststørrelse")
        }
        waitStatus(["firebase=off", "opened=0", "played=0"])
    }

    func testListeningCardsKeepFullTouchTargetsAndTheirOriginalActions() {
        launch("owner")
        tapFixture("home.fixture.position")
        let resume = app.buttons["home.resume.play"]
        reveal(resume, fullyVisible: true)
        XCTAssertEqual(resume.label, "Fortsæt")
        XCTAssertGreaterThanOrEqual(resume.frame.width + 0.001, 44)
        XCTAssertGreaterThanOrEqual(resume.frame.height + 0.001, 44)
        let resumeCard = app.otherElements["home.resume.card"]
        assertReadableAudioText("home.resume.playLabel", expected: "Fortsæt", card: resumeCard, button: resume)
        capture("Home — læsbart Fortsæt med den valgte tekststørrelse")
        resume.tap()
        waitStatus(["played=1", "opened=0"])

        let play = app.buttons["home.podcast.play.audio-hero"]
        reveal(play, fullyVisible: true)
        XCTAssertGreaterThanOrEqual(play.frame.width + 0.001, 44)
        XCTAssertGreaterThanOrEqual(play.frame.height + 0.001, 44)
        let audioCard = app.otherElements["home.podcast.card.audio-hero"]
        assertReadableAudioText("home.podcast.duration.audio-hero", expected: "10 min", card: audioCard)
        assertReadableAudioText("home.podcast.playLabel.audio-hero", expected: "Lyt", card: audioCard, button: play)
        play.tap()
        waitStatus(["played=2", "opened=0", "firebase=off", "builds=1"])
        capture("Home — oprindelige lydknapper med fulde trykflader")
    }

    func testHeroReachesTheScreenTopInsideTheNativeTabAndNavigationContainers() {
        launch("edge")
        let hero = app.scrollViews["home.hero.carousel"]
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        let author = app.staticTexts["home.hero.author.hero-1"]
        let category = app.staticTexts["home.hero.category.hero-1.0"]
        let secondCategory = app.staticTexts["home.hero.category.hero-1.1"]
        XCTAssertTrue(author.exists)
        XCTAssertTrue(category.exists)
        XCTAssertTrue(secondCategory.exists)
        XCTAssertEqual(category.label, "KULTUR")
        XCTAssertEqual(secondCategory.label, "DESIGN")
        XCTAssertEqual(author.frame.midY, category.frame.midY, accuracy: 1,
            "Forfatter og kategorier skal ligge ved siden af hinanden i heroen")
        XCTAssertEqual(category.frame.midY, secondCategory.frame.midY, accuracy: 1)
        XCTAssertLessThanOrEqual(author.frame.maxX, category.frame.minX)
        XCTAssertLessThanOrEqual(category.frame.maxX, secondCategory.frame.minX)
        capture("Home — heroens øverste kant i appens native navigation")
        XCTAssertEqual(hero.frame.minY, app.frame.minY, accuracy: 1,
            "Heroen skal begynde ved skærmens øverste kant, også bag statuslinjen")
        XCTAssertGreaterThan(hero.frame.height, 420)
        XCTAssertTrue(app.tabBars.firstMatch.exists)
    }

    func testCachedHomeUsesPreparedMetadataAndTheFullTypedSeeAllPayload() {
        launch("cache")
        reveal(app.buttons["home.hero.title.hero-1"])
        XCTAssertEqual(app.staticTexts["home.hero.tag.hero-1"].label, "Kultur")
        XCTAssertEqual(app.staticTexts["home.hero.author.hero-1"].label, "Signe Jensen")
        capture("Home — cached hero med forberedt kategori og korrekt byline")
        let favorite = app.buttons["home.hero.favorite.hero-1"]
        tap(favorite)
        waitStatus(["favorites=1", "opened=0", "builds=1"])
        XCTAssertEqual(favorite.label, "Fjern fra gemte artikler")
        XCTAssertFalse(app.staticTexts["home.fixture.openedArticle"].exists)
        reveal(app.buttons["home.card.recommended.music-1"])
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "home.favorite.")).firstMatch.exists)
        capture("Home — coverbilleder uden bookmark-overlays")
        tap(app.buttons["home.seeAll.music"])
        let count = app.staticTexts["home.list.count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5)); XCTAssertEqual(count.label, "8 artikler")
        let last = app.buttons["home.list.article.music-8"]
        reveal(last, in: "home.list")
        XCTAssertTrue(last.label.contains("Musikkens nye stemmer 8"))
        XCTAssertTrue(last.label.contains("Signe Jensen"))
        capture("Home — Musik Se alle indeholder også artikler ud over de seks synlige kort")
        tap(last, in: "home.list")
        let opened = app.staticTexts["home.fixture.openedArticle"]
        XCTAssertTrue(opened.waitForExistence(timeout: 5)); XCTAssertEqual(opened.label, "Musikkens nye stemmer 8")
        waitStatus(["firebase=off", "builds=1", "preparing=0"])
    }

    func testWithdrawalAndAnOldHeldPreparationCannotRestoreCardsOrStartAudio() {
        launch("withdrawal")
        let hero = reveal(app.buttons["home.hero.title.hero-1"])
        hero.swipeLeft()
        let position = app.descendants(matching: .any).matching(identifier: "home.hero.position").firstMatch
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "2 af 5"), object: position)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed)
        tap(app.buttons["home.podcast.play.audio-hero"])
        waitStatus(["actions=1", "played=0"])
        tapFixture("home.fixture.hold"); waitStatus(["held=1", "preparing=1"])
        tapFixture("home.fixture.withdraw")
        waitAbsent(app.buttons["home.hero.read.hero-1"])
        waitAbsent(app.buttons["home.podcast.play.audio-hero"])
        waitStatus(["held=1", "preparing=1", "played=0"])
        tapFixture("home.fixture.release")
        waitStatus(["held=0", "actions=0", "denied=1", "played=0", "builds=3", "preparing=0"])
        reveal(app.buttons["home.hero.title.hero-2"])
        XCTAssertEqual(position.value as? String, "1 af 5")
        XCTAssertFalse(app.buttons["home.hero.read.hero-1"].exists)
        XCTAssertFalse(app.buttons["home.podcast.play.audio-hero"].exists)
        capture("Home — tilbagekaldelse består efter gammelt svar, og gammel lydhandling er afvist")
    }

    func testProgressAndReducedMotionKeepPreparationStableAndAccountBReplacesRecommendations() {
        launch("owner", reducedMotion: true)
        waitStatus(["owner=A", "homeReduce=1"])
        reveal(app.buttons["home.card.recommended.music-1"])
        let builds = metric("builds"), sorts = metric("sorts"), matches = metric("matches")
        tapFixture("home.fixture.position")
        reveal(app.buttons["home.resume.play"])
        XCTAssertEqual(app.buttons["home.resume.play"].label, "Fortsæt")
        XCTAssertEqual(metric("builds"), builds); XCTAssertEqual(metric("sorts"), sorts); XCTAssertEqual(metric("matches"), matches)
        capture("Home — lytteposition viser fælles fortsæt-banner med reduceret Home-bevægelse")
        tapFixture("home.fixture.active"); waitAbsent(app.buttons["home.resume.play"])
        XCTAssertEqual(metric("builds"), builds); XCTAssertEqual(metric("sorts"), sorts); XCTAssertEqual(metric("matches"), matches)
        tapFixture("home.fixture.ownerB"); waitStatus(["owner=B", "preparing=0"])
        reveal(app.buttons["home.card.recommended.culture-1"])
        XCTAssertFalse(app.buttons["home.card.recommended.music-1"].exists)
        XCTAssertTrue(app.staticTexts["For dine interesser i kultur"].exists)
        XCTAssertFalse(app.buttons["home.resume.play"].exists)
        XCTAssertGreaterThan(metric("builds"), builds)
        waitStatus(["firebase=off", "owner=B", "homeReduce=1"])
        capture("Home — konto B viser kun sit personlige udvalg og ingen gammel lytteposition")
    }
    private func compactReport(_ favoriteRows: Bool = false) -> [String: Any] {
        let element = app.staticTexts[favoriteRows ? "home.favoriteRows.geometry" : "home.compact.geometry"]
        guard let text = element.value as? String, let data = text.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return payload
    }
    private func compactFrame(_ key: String, report: [String: Any], file: StaticString = #filePath, line: UInt = #line) -> CGRect {
        guard let frames = report["frames"] as? [String: [String: Double]], let frame = frames[key],
              let x = frame["x"], let y = frame["y"], let width = frame["width"], let height = frame["height"] else {
            XCTFail("Missing production row geometry: \(key)", file: file, line: line); return .zero
        }
        XCTAssertGreaterThan(width, 0, file: file, line: line)
        XCTAssertGreaterThan(height, 0, file: file, line: line)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Cropped artwork can expose its intrinsic AX bounds beyond the visible clip.
    /// Reveal the actual production image/content frames, keeping full visibility required.
    private func revealCompactRow(_ id: String, favoriteRows: Bool = false, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let row = favoriteRows
            ? app.descendants(matching: .any).matching(identifier: "home.favoriteRows.row." + id).firstMatch
            : app.otherElements["home.compact.row." + id]
        let scroller = favoriteRows
            ? app.descendants(matching: .any).matching(identifier: "home.fixture.favoriteRows").firstMatch
            : app.scrollViews["home.fixture.compactRows"]
        XCTAssertTrue(scroller.waitForExistence(timeout: 5), file: file, line: line)
        for attempt in 0...24 {
            let viewport = scroller.frame.intersection(app.frame)
            let bounds = CGRect(x: viewport.minX + 12, y: viewport.minY + 12,
                width: max(1, viewport.width - 24), height: max(1, viewport.height - 28))
            var down = true
            var edgeDistance: CGFloat?
            let report = compactReport(favoriteRows)
            if row.exists, let frames = report["frames"] as? [String: [String: Double]],
               frames[id + ".image"] != nil, frames[id + ".content"] != nil {
                let target = compactFrame(id + ".image", report: report, file: file, line: line)
                    .union(compactFrame(id + ".content", report: report, file: file, line: line))
                if !target.isEmpty, target.midY.isFinite {
                    let fullyVisible = bounds.insetBy(dx: -1, dy: -1).contains(target)
                    if fullyVisible, row.isHittable {
                        XCTAssertTrue(bounds.insetBy(dx: -1, dy: -1).contains(target),
                            "Actual image and complete text content must fit the visible viewport", file: file, line: line)
                        return row
                    }
                    down = target.midY >= bounds.midY
                    if target.minY < bounds.minY { down = false; edgeDistance = bounds.minY - target.minY + 12 }
                    else if target.maxY > bounds.maxY { down = true; edgeDistance = target.maxY - bounds.maxY + 12 }
                }
            }
            guard attempt < 24 else { break }
            let distance = min(min(380, bounds.height * 0.68), edgeDistance ?? .greatestFiniteMagnitude)
            let startY = down ? bounds.midY + distance / 2 : bounds.midY - distance / 2
            let endY = down ? bounds.midY - distance / 2 : bounds.midY + distance / 2
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: bounds.midX, dy: startY)).press(forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: bounds.midX, dy: endY)))
        }
        XCTFail("Actual compact row content outside the viewport: \(id)", file: file, line: line)
        return row
    }

    func testCompactCategoryRowsFillTheirContentHeightAndShowOnlyPositiveRatings() {
        launch("compactRows")
        let samples: [(id: String, rating: Int?)] = [
            ("compact-rated-five", 5), ("compact-rated-six", 6), ("compact-unrated", nil), ("compact-zero", nil)
        ]
        var heights: [String: CGFloat] = [:]
        for sample in samples {
            let row = revealCompactRow(sample.id)
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
                guard let frames = self?.compactReport()["frames"] as? [String: [String: Double]] else { return false }
                return ["image", "content", "title", "category"].allSatisfy { frames[sample.id + "." + $0] != nil }
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
            let report = compactReport()
            let image = compactFrame(sample.id + ".image", report: report)
            let content = compactFrame(sample.id + ".content", report: report)
            let title = compactFrame(sample.id + ".title", report: report)
            let category = compactFrame(sample.id + ".category", report: report)
            XCTAssertEqual(image.width, 80, accuracy: 1.0 / 3.0)
            XCTAssertEqual(image.minY, title.minY, accuracy: 1.0 / 3.0, "Artwork starts at the actual title top")
            XCTAssertEqual(image.maxY, category.maxY, accuracy: 1.0 / 3.0, "Artwork reaches the actual metadata bottom")
            XCTAssertEqual(image.height, content.height, accuracy: 1.0 / 3.0)
            XCTAssertEqual(content.minY, title.minY, accuracy: 1.0 / 3.0)
            XCTAssertEqual(content.maxY, category.maxY, accuracy: 1.0 / 3.0)
            XCTAssertEqual(content.minX - image.maxX, 12, accuracy: 1.0 / 3.0)
            XCTAssertTrue(content.insetBy(dx: -1.0 / 3.0, dy: -1.0 / 3.0).contains(title))
            XCTAssertTrue(content.insetBy(dx: -1.0 / 3.0, dy: -1.0 / 3.0).contains(category))
            heights[sample.id] = image.height
            let rating = row.otherElements["article.compact.rating." + sample.id]
            if let expected = sample.rating {
                XCTAssertTrue(rating.exists)
                XCTAssertEqual(rating.label, "\(expected) ud af 6 stjerner")
                let stars = compactFrame(sample.id + ".rating", report: report)
                XCTAssertTrue(content.insetBy(dx: -1.0 / 3.0, dy: -1.0 / 3.0).contains(stars))
                XCTAssertGreaterThanOrEqual(stars.minY, title.maxY)
                XCTAssertLessThanOrEqual(stars.maxY, category.minY)
            } else {
                XCTAssertFalse(rating.exists)
                let frames = report["frames"] as? [String: [String: Double]]
                XCTAssertNil(frames?[sample.id + ".rating"], "Nil and zero scores do not reserve a star row")
            }
            XCTAssertEqual(report["firebaseStarted"] as? Bool, false)
            let attachment = XCTAttachment(string: String(describing: report))
            attachment.name = "Actual compact row geometry — " + sample.id
            attachment.lifetime = .keepAlways; add(attachment)
            capture("Kategorikort — fuld billedhøjde og korrekt rating — " + sample.id)
        }
        XCTAssertGreaterThan(heights["compact-rated-five"] ?? 0, heights["compact-rated-six"] ?? 0,
            "The image follows real long versus short row height, not a shared fixed height")
        let shortRow = revealCompactRow("compact-rated-six")
        XCTAssertTrue(shortRow.buttons.firstMatch.exists)
        shortRow.buttons.firstMatch.tap()
        let destination = app.staticTexts["home.compact.destination"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        XCTAssertEqual(destination.label, "Byliv")
        capture("Kategorikort — eksisterende rækkeknap åbner lokal artikel")
        app.buttons["home.compact.return"].tap()
        XCTAssertTrue(app.scrollViews["home.fixture.compactRows"].waitForExistence(timeout: 5))
        XCTAssertEqual(compactReport()["openedCount"] as? Int, 1)
        XCTAssertEqual(compactReport()["selectedID"] as? String, "")
        waitStatus(["firebase=off", "played=0"])
    }

    private func waitFavoriteImage(_ id: String, state: String, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            (self?.compactReport(true)["states"] as? [String: String])?[id] == state
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed, file: file, line: line)
        XCTAssertEqual(compactReport(true)["error"] as? String, "", file: file, line: line)
    }

    @discardableResult
    private func assertFavoriteGeometry(_ id: String, rating: Int?, file: StaticString = #filePath, line: UInt = #line) -> CGRect {
        let row = revealCompactRow(id, favoriteRows: true, file: file, line: line)
        let report = compactReport(true)
        let image = compactFrame(id + ".image", report: report, file: file, line: line)
        let content = compactFrame(id + ".content", report: report, file: file, line: line)
        let title = compactFrame(id + ".title", report: report, file: file, line: line)
        let category = compactFrame(id + ".category", report: report, file: file, line: line)
        let intro = compactFrame(id + ".intro", report: report, file: file, line: line)
        let tolerance: CGFloat = 1.0 / 3.0 + 0.001
        XCTAssertEqual(image.width, 80, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(image.minY, title.minY, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(image.maxY, intro.maxY, accuracy: tolerance,
            "The actual favorite image reaches the bottom of its final text", file: file, line: line)
        XCTAssertEqual(image.height, content.height, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(content.minX - image.maxX, 16, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(content.minY, title.minY, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(content.maxY, intro.maxY, accuracy: tolerance, file: file, line: line)
        for frame in [title, category, intro] {
            XCTAssertTrue(content.insetBy(dx: -tolerance, dy: -tolerance).contains(frame), file: file, line: line)
        }
        XCTAssertLessThanOrEqual(title.maxY, category.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(category.maxY, intro.minY, file: file, line: line)
        let stars = row.otherElements["article.favorite.rating." + id]
        if let rating {
            XCTAssertTrue(stars.exists, file: file, line: line)
            XCTAssertEqual(stars.label, "\(rating) ud af 6 stjerner", file: file, line: line)
            let starFrame = compactFrame(id + ".rating", report: report, file: file, line: line)
            XCTAssertTrue(content.insetBy(dx: -tolerance, dy: -tolerance).contains(starFrame), file: file, line: line)
            XCTAssertLessThanOrEqual(title.maxY, starFrame.minY, file: file, line: line)
            XCTAssertLessThanOrEqual(starFrame.maxY, category.minY, file: file, line: line)
        } else {
            XCTAssertFalse(stars.exists, file: file, line: line)
            XCTAssertNil((report["frames"] as? [String: [String: Double]])?[id + ".rating"], file: file, line: line)
        }
        XCTAssertEqual(report["firebaseStarted"] as? Bool, false, file: file, line: line)
        let attachment = XCTAttachment(string: String(describing: report))
        attachment.name = "Actual favorite row geometry — " + id; attachment.lifetime = .keepAlways; add(attachment)
        return image
    }

    func testFavoriteRowsFillContentHeightShowRatingsAndRecoverLocalArtwork() {
        launch("favoriteRows")
        let samples: [(id: String, rating: Int?, state: String)] = [
            ("favorite-five", 5, "loaded"), ("favorite-six", 6, "loaded"),
            ("favorite-unrated", nil, "failed"), ("favorite-zero", nil, "failed")
        ]
        var heights: [String: CGFloat] = [:]
        for sample in samples {
            _ = revealCompactRow(sample.id, favoriteRows: true)
            waitFavoriteImage(sample.id, state: sample.state)
            heights[sample.id] = assertFavoriteGeometry(sample.id, rating: sample.rating).height
            capture("Gemte artikler — fuld billedhøjde og rigtig rating — " + sample.id)
        }
        XCTAssertGreaterThan(heights["favorite-five"] ?? 0, heights["favorite-six"] ?? 0,
            "Images follow their own real long/short content, not a shared 80 pt height")
        let before = assertFavoriteGeometry("favorite-unrated", rating: nil)
        tapFixture("home.favoriteRows.replace")
        waitFavoriteImage("favorite-unrated", state: "loaded")
        let after = assertFavoriteGeometry("favorite-unrated", rating: nil)
        XCTAssertEqual(after.width, before.width, accuracy: 1.0 / 3.0 + 0.001)
        XCTAssertEqual(after.height, before.height, accuracy: 1.0 / 3.0 + 0.001,
            "Actual local-file replacement must not change the favorite's content height")
        XCTAssertEqual(compactReport(true)["replaced"] as? Bool, true)
        capture("Gemte artikler — faktisk grønt lokalt erstatningsbillede uden højdespring")
        let row = revealCompactRow("favorite-six", favoriteRows: true)
        // The iPad accessibility tree also exposes the rating as a nested button.
        // Tap the visible article title rather than that unrelated first element.
        let rowAction = row.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Wolverine")).firstMatch
        XCTAssertTrue(rowAction.exists); XCTAssertTrue(rowAction.isHittable); rowAction.tap()
        let destination = app.staticTexts["home.favoriteRows.destination"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5)); XCTAssertEqual(destination.label, "Wolverine")
        capture("Gemte artikler — eksisterende rækkeknap åbner lokal artikel")
        tapFixture("home.favoriteRows.return")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "home.fixture.favoriteRows").firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(compactReport(true)["openedCount"] as? Int, 1)
        XCTAssertEqual(compactReport(true)["selectedID"] as? String, "")
        let report = compactReport(true)
        XCTAssertEqual(report["environmentAccessibility"] as? Bool, report["systemAccessibility"] as? Bool,
            "Fixture controls may be compact, but the actual rows follow system text size")
        waitStatus(["firebase=off", "played=0"])
    }

    private func favoriteControlsReport() -> [String: Any] {
        let element = app.staticTexts["home.favoriteControls.geometry"]
        guard let text = element.value as? String, let data = text.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return payload
    }
    private func waitFavoriteControls(category: String, sort: String = "Titel A-Å", searchRequests: Int = 0,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let diagnostic = app.staticTexts["home.favoriteControls.geometry"]
        XCTAssertTrue(diagnostic.waitForExistence(timeout: 5), file: file, line: line)
        let predicate = NSPredicate { [weak self] _, _ in
            guard let self else { return false }
            let report = self.favoriteControlsReport()
            let frames = report["frames"] as? [String: [String: Double]] ?? [:]
            return report["selectedCategory"] as? String == category
                && report["selectedSort"] as? String == sort
                && report["searchRequests"] as? Int == searchRequests
                && ["viewport", "container", "sort", "sort.pill", "sort.text", "category", "category.pill",
                    "category.text", "search", "count"].allSatisfy { frames[$0] != nil }
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: diagnostic)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed, file: file, line: line)
    }
    private func assertFavoriteControlsGeometry(_ phase: String, file: StaticString = #filePath, line: UInt = #line) {
        let report = favoriteControlsReport()
        let text = app.staticTexts["home.favoriteControls.geometry"].value as? String ?? "{}"
        let attachment = XCTAttachment(string: text)
        attachment.name = "Favorite controls actual geometry — " + phase
        attachment.lifetime = .keepAlways; add(attachment)
        capture("Min side — actual controls — " + phase)
        XCTAssertEqual(report["firebaseStarted"] as? Bool, false, file: file, line: line)
        XCTAssertEqual(report["environmentAccessibility"] as? Bool, report["systemAccessibility"] as? Bool,
            "Only fixture diagnostics may cap text size; actual controls must follow the system", file: file, line: line)
        let viewport = compactFrame("viewport", report: report, file: file, line: line).intersection(app.frame)
        let category = compactFrame("category.pill", report: report, file: file, line: line)
        let label = compactFrame("category.text", report: report, file: file, line: line)
        XCTAssertTrue(category.insetBy(dx: -1, dy: -1).contains(label),
            "The actual selected category text must fit inside its clipped pill", file: file, line: line)
        let sort = compactFrame("sort.pill", report: report, file: file, line: line)
        let sortText = compactFrame("sort.text", report: report, file: file, line: line)
        XCTAssertTrue(sort.insetBy(dx: -1, dy: -1).contains(sortText), file: file, line: line)
        let identifiers = ["sort", "category", "search", "count"]
        let visibleFrames = identifiers.map { compactFrame($0, report: report, file: file, line: line) }
        for (index, frame) in visibleFrames.enumerated() {
            XCTAssertTrue(viewport.insetBy(dx: -1, dy: -1).contains(frame),
                "The entire \(identifiers[index]) control must be visible inside the List viewport", file: file, line: line)
            for earlier in visibleFrames.prefix(index) {
                let overlap = frame.intersection(earlier)
                XCTAssertTrue(overlap.isNull || overlap.width * overlap.height < 0.001,
                    "Independent favorite controls must not overlap", file: file, line: line)
            }
            if identifiers[index] != "count" {
                XCTAssertGreaterThanOrEqual(frame.width + 0.001, 44, file: file, line: line)
                XCTAssertGreaterThanOrEqual(frame.height + 0.001, 44,
                    "Every menu/search action must keep a 44 pt target", file: file, line: line)
                let control = app.buttons["favorites.controls." + identifiers[index]].firstMatch
                XCTAssertTrue(control.exists, file: file, line: line)
                XCTAssertTrue(control.isHittable, file: file, line: line)
                switch identifiers[index] {
                case "sort":
                    XCTAssertEqual(control.label, "Sortering", file: file, line: line)
                    XCTAssertEqual(control.value as? String, report["selectedSort"] as? String, file: file, line: line)
                case "category":
                    XCTAssertEqual(control.label, "Emne", file: file, line: line)
                    XCTAssertEqual(control.value as? String, report["selectedCategory"] as? String, file: file, line: line)
                case "search":
                    XCTAssertEqual(control.label, "Søg i artikler", file: file, line: line)
                default: break
                }
            }
        }
    }
    private func selectFavoriteControl(_ control: String, option: String,
                                       file: StaticString = #filePath, line: UInt = #line) {
        let menu = app.buttons["favorites.controls." + control].firstMatch
        XCTAssertTrue(menu.exists, file: file, line: line)
        XCTAssertTrue(menu.isHittable, file: file, line: line); menu.tap()
        let choice = app.buttons["favorites.controls." + control + ".option." + option].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(choice.isHittable, file: file, line: line); choice.tap()
    }

    func testFavoriteControlsKeepLongCategoryVisibleAndActionsReachableAtSystemTextSize() {
        launch("favoriteControls")
        waitFavoriteControls(category: "Kultur & Mening")
        XCTAssertEqual(favoriteControlsReport()["articleCount"] as? Int, 1)
        assertFavoriteControlsGeometry("long category")

        selectFavoriteControl("category", option: "Film")
        waitFavoriteControls(category: "Film")
        XCTAssertEqual(favoriteControlsReport()["articleCount"] as? Int, 2)
        assertFavoriteControlsGeometry("short category")
        selectFavoriteControl("category", option: "Kultur & Mening")
        waitFavoriteControls(category: "Kultur & Mening")
        XCTAssertEqual(favoriteControlsReport()["articleCount"] as? Int, 1)

        selectFavoriteControl("sort", option: "Bedst bedømt")
        waitFavoriteControls(category: "Kultur & Mening", sort: "Bedst bedømt")
        assertFavoriteControlsGeometry("selected rating sort and long category")
        let search = app.buttons["favorites.controls.search"].firstMatch
        XCTAssertTrue(search.isHittable); search.tap()
        waitFavoriteControls(category: "Kultur & Mening", sort: "Bedst bedømt", searchRequests: 1)
        waitStatus(["firebase=off", "played=0"])
    }

    private func homeNavigationReport() -> [String: Any] {
        guard let value = app.staticTexts["home.navigation.state"].value as? String,
              let bytes = value.data(using: .utf8),
              let report = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return [:] }
        return report
    }
    private func selectHomeFixtureTab(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let tab = app.tabBars.buttons[label].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(tab.isHittable, file: file, line: line); tab.tap()
        let predicate = NSPredicate { [weak self] _, _ in self?.homeNavigationReport()["selectedTab"] as? String == label }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app.staticTexts["home.navigation.state"])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }
    private func captureHomeNavigation(_ phase: String) {
        let attachment = XCTAttachment(string: app.staticTexts["home.navigation.state"].value as? String ?? "{}")
        attachment.name = "Actual Home navigation — " + phase; attachment.lifetime = .keepAlways; add(attachment)
        capture("Home navigation — " + phase)
    }
    private func assertHomeRootWithoutScrolling(_ originalHeroTop: CGFloat, phase: String,
                                                file: StaticString = #filePath, line: UInt = #line) {
        let hero = app.scrollViews["home.hero.carousel"]
        let feed = app.scrollViews["home.feed"]
        let predicate = NSPredicate { _, _ in
            hero.exists && hero.isHittable && feed.exists && feed.isHittable
                && abs(hero.frame.minY - originalHeroTop) <= 1
                && !self.app.scrollViews["home.podcast.list"].exists
                && !self.app.scrollViews["home.list"].exists
                && !self.app.staticTexts["home.navigation.article"].exists
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: hero)
        let result = XCTWaiter.wait(for: [expectation], timeout: 8)
        // Capture the actual still-visible destination before asserting, including
        // a failed reset. Never scroll/reveal Home to manufacture the top state.
        captureHomeNavigation(phase)
        XCTAssertEqual(result, .completed, "Tab selection must reveal the real Home root at its original top", file: file, line: line)
        XCTAssertEqual(hero.frame.minY, originalHeroTop, accuracy: 1, file: file, line: line)
        let report = homeNavigationReport()
        XCTAssertEqual(report["firebaseStarted"] as? Bool, false, file: file, line: line)
        XCTAssertEqual(report["homePathCount"] as? Int, 0, file: file, line: line)
        XCTAssertEqual(report["searchPathCount"] as? Int, 1, "Resetting Home must preserve the other tab's real path", file: file, line: line)
    }
    private func prepareHomeReselectionFixture() -> CGFloat {
        launch("tabReselect")
        let hero = app.scrollViews["home.hero.carousel"]
        XCTAssertTrue(hero.waitForExistence(timeout: 5)); XCTAssertTrue(hero.isHittable)
        let originalTop = hero.frame.minY
        selectHomeFixtureTab("Artikler")
        let open = app.buttons["home.navigation.search.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5)); XCTAssertTrue(open.isHittable); open.tap()
        XCTAssertTrue(app.staticTexts["home.navigation.search.destination"].waitForExistence(timeout: 5))
        XCTAssertEqual(homeNavigationReport()["searchPathCount"] as? Int, 1)
        selectHomeFixtureTab("Hjem")
        assertHomeRootWithoutScrolling(originalTop, phase: "initial Home with another tab retained")
        return originalTop
    }
    private func assertOtherTabDestinationPreserved() {
        selectHomeFixtureTab("Artikler")
        XCTAssertTrue(app.staticTexts["home.navigation.search.destination"].waitForExistence(timeout: 5))
        XCTAssertEqual(homeNavigationReport()["searchPathCount"] as? Int, 1)
    }

    func testHomeTabReselectionAndCrossTabReturnLeavePodcastSeeAllAtTheHomeRoot() {
        let originalTop = prepareHomeReselectionFixture()
        tap(app.buttons["home.seeAll.podcasts"])
        XCTAssertTrue(app.scrollViews["home.podcast.list"].waitForExistence(timeout: 5))
        captureHomeNavigation("podcast See alle before same-tab reselect")
        selectHomeFixtureTab("Hjem")
        assertHomeRootWithoutScrolling(originalTop, phase: "podcast same-tab reselect")

        tap(app.buttons["home.seeAll.podcasts"])
        XCTAssertTrue(app.scrollViews["home.podcast.list"].waitForExistence(timeout: 5))
        assertOtherTabDestinationPreserved()
        selectHomeFixtureTab("Hjem")
        assertHomeRootWithoutScrolling(originalTop, phase: "podcast See alle through Artikler and back Home")
        waitStatus(["firebase=off", "played=0", "opened=0"])
    }

    func testHomeTabReselectionAndCrossTabReturnLeaveMusicSeeAllAndNestedArticleAtTheHomeRoot() {
        let originalTop = prepareHomeReselectionFixture()
        tap(app.buttons["home.seeAll.music"])
        XCTAssertTrue(app.scrollViews["home.list"].waitForExistence(timeout: 5))
        captureHomeNavigation("music See alle before same-tab reselect")
        selectHomeFixtureTab("Hjem")
        assertHomeRootWithoutScrolling(originalTop, phase: "music same-tab reselect")

        tap(app.buttons["home.seeAll.music"])
        XCTAssertTrue(app.scrollViews["home.list"].waitForExistence(timeout: 5))
        assertOtherTabDestinationPreserved()
        selectHomeFixtureTab("Hjem")
        assertHomeRootWithoutScrolling(originalTop, phase: "music See alle through Artikler and back Home")

        tap(app.buttons["home.seeAll.music"])
        tap(app.buttons["home.list.article.music-1"], in: "home.list")
        XCTAssertTrue(app.staticTexts["home.navigation.article"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["home.navigation.article"].label, "Musikkens nye stemmer 1")
        XCTAssertEqual(homeNavigationReport()["homePathCount"] as? Int, 1)
        captureHomeNavigation("music nested article in actual coordinator path")
        selectHomeFixtureTab("Hjem")
        assertHomeRootWithoutScrolling(originalTop, phase: "nested article same-tab reselect")
        assertOtherTabDestinationPreserved()
        selectHomeFixtureTab("Hjem")
        assertHomeRootWithoutScrolling(originalTop, phase: "final other-tab path remains intact")
        waitStatus(["firebase=off", "played=0", "opened=0"])
    }

    private func tabProbeTap(_ identifier: String) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(button.isHittable)
        button.tap()
    }
    private func tabProbeWait(_ phase: String, condition: @escaping ([String: Any]) -> Bool) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            guard let self else { return false }
            return condition(self.homeNavigationReport())
        }, object: app.staticTexts["home.navigation.state"])
        let result = XCTWaiter.wait(for: [expected], timeout: 8)
        captureTabProbe(phase)
        XCTAssertEqual(result, .completed, phase)
    }
    private func captureTabProbe(_ phase: String) {
        let original = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        original.name = "Active tab root — " + phase; original.lifetime = .keepAlways; add(original)
        let raw = app.staticTexts["home.navigation.state"].value as? String ?? "{}"
        let receipt = XCTAttachment(data: Data(raw.utf8), uniformTypeIdentifier: "public.json")
        receipt.name = "Active tab paths/root state/player — " + phase; receipt.lifetime = .keepAlways; add(receipt)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Active tab AX — " + phase; tree.lifetime = .keepAlways; add(tree)
    }
    private func tabProbeRootState() -> [String: Any] {
        homeNavigationReport()["rootStates"] as? [String: Any] ?? [:]
    }
    private func prepareTabProbe() -> [String: Any] {
        launch("allTabReselect")
        XCTAssertEqual(homeNavigationReport()["actualShell"] as? Bool, true)
        XCTAssertEqual(homeNavigationReport()["normalPlayerOrReaderStarted"] as? Bool, false)
        let pause = app.buttons["podcast.mini.playPause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5)); XCTAssertTrue(pause.isHittable); pause.tap()
        tabProbeWait("actual mini memory paused before navigating") { report in
            let player = report["playerMemory"] as? [String: Any] ?? [:]
            return player["isPlaying"] as? Bool == false && player["pauseActions"] as? Int == 1
        }
        return homeNavigationReport()["playerMemory"] as? [String: Any] ?? [:]
    }
    private func tabProbeChooseRoot(_ label: String, id: String) {
        selectHomeFixtureTab(label)
        let root = app.staticTexts["tabs.reselect.root." + id]
        XCTAssertTrue(root.waitForExistence(timeout: 5)); XCTAssertTrue(root.isHittable)
        tabProbeTap("tabs.reselect.choice." + id)
        tabProbeWait("retained local choice for " + id) { report in
            let states = report["rootStates"] as? [String: [String: Any]] ?? [:]
            return states[id]?["choice"] as? Int == 1
        }
    }
    private func tabProbeOpenSearch(nested: Bool = false) {
        tabProbeTap("home.navigation.search.open")
        XCTAssertTrue(app.staticTexts["home.navigation.search.destination"].waitForExistence(timeout: 5))
        if nested {
            tabProbeTap("tabs.reselect.nestedArticle.search")
            XCTAssertTrue(app.staticTexts["tabs.reselect.article.search"].waitForExistence(timeout: 5))
        }
    }
    private func tabProbeOpenCategory(nested: Bool) {
        tabProbeTap("tabs.reselect.open.categories")
        XCTAssertTrue(app.staticTexts["tabs.reselect.category.destination"].waitForExistence(timeout: 5))
        if nested {
            tabProbeTap("tabs.reselect.nestedArticle.categories")
            XCTAssertTrue(app.staticTexts["tabs.reselect.article.categories"].waitForExistence(timeout: 5))
        }
    }
    private func tabProbeOpenFavorite() {
        tabProbeTap("tabs.reselect.open.favorites")
        XCTAssertTrue(app.staticTexts["tabs.reselect.article.favorites"].waitForExistence(timeout: 5))
    }
    private func assertTabProbeRetained(paths: [String: Int], rootStates: [String: Any], player: [String: Any]) {
        let report = homeNavigationReport()
        for (key, value) in paths { XCTAssertEqual(report[key] as? Int, value, key) }
        XCTAssertTrue(NSDictionary(dictionary: tabProbeRootState()).isEqual(to: rootStates),
            "Popping only the selected path must retain the roots' actual @State identity and local choice")
        XCTAssertTrue(NSDictionary(dictionary: report["playerMemory"] as? [String: Any] ?? [:]).isEqual(to: player),
            "Tab navigation must retain the injected player's identity, paused value and callback counts")
        XCTAssertEqual(report["firebaseStarted"] as? Bool, false)
        XCTAssertTrue(app.buttons["podcast.mini.playPause"].exists)
    }
    private func assertTabProbeReset(_ label: String, id: String, path: String,
                                     retained: [String: Int], roots: [String: Any], player: [String: Any]) {
        // Real UITabBar press only. No direct coordinator reset, fallback back
        // gesture or synthetic route deletion is available to the test.
        selectHomeFixtureTab(label)
        tabProbeWait("active " + id + " returns to the visible root") { report in
            let root = self.app.staticTexts["tabs.reselect.root." + id]
            return report[path] as? Int == 0 && root.exists && root.isHittable
                && !self.app.staticTexts["tabs.reselect.more.destination." + id].exists
                && !self.app.staticTexts["tabs.reselect.article." + id].exists
        }
        assertTabProbeRetained(paths: retained.merging([path: 0], uniquingKeysWith: { _, new in new }),
            rootStates: roots, player: player)
        let homeStackID = homeNavigationReport()["homeStackID"] as? String
        selectHomeFixtureTab(label)
        captureTabProbe("repeated root press on " + id)
        assertTabProbeRetained(paths: retained.merging([path: 0], uniquingKeysWith: { _, new in new }),
            rootStates: roots, player: player)
        XCTAssertEqual(homeNavigationReport()["homeStackID"] as? String, homeStackID,
            "A non-Home root press must not recreate Home or another root")
    }

    func testArticlesTabReselectionReturnsFromNestedArticleAndPreservesOtherTabs() {
        let player = prepareTabProbe()
        tabProbeChooseRoot("Kategorier", id: "categories"); tabProbeOpenCategory(nested: true)
        tabProbeChooseRoot("Min side", id: "favorites"); tabProbeOpenFavorite()
        tabProbeChooseRoot("Artikler", id: "search"); tabProbeOpenSearch(nested: true)
        let roots = tabProbeRootState()
        captureTabProbe("before active Artikler at typed article over retained String path")
        assertTabProbeRetained(paths: ["searchPathCount": 2, "categoriesPathCount": 2, "favoritesPathCount": 1],
            rootStates: roots, player: player)
        assertTabProbeReset("Artikler", id: "search", path: "searchPathCount",
            retained: ["categoriesPathCount": 2, "favoritesPathCount": 1], roots: roots, player: player)
        selectHomeFixtureTab("Kategorier")
        XCTAssertTrue(app.staticTexts["tabs.reselect.article.categories"].waitForExistence(timeout: 5),
            "An ordinary cross-tab switch restores the other tab's retained path")
        captureTabProbe("ordinary switch restores Categories article")
        assertTabProbeRetained(paths: ["searchPathCount": 0, "categoriesPathCount": 2, "favoritesPathCount": 1],
            rootStates: roots, player: player)
    }

    func testCategoriesTabReselectionClosesTypedParentsAndViewDestination() {
        let player = prepareTabProbe()
        tabProbeChooseRoot("Artikler", id: "search"); tabProbeOpenSearch()
        tabProbeChooseRoot("Min side", id: "favorites"); tabProbeOpenFavorite()
        tabProbeChooseRoot("Kategorier", id: "categories"); tabProbeOpenCategory(nested: true)
        XCTAssertEqual(homeNavigationReport()["categoriesPathCount"] as? Int, 2,
            "The real typed category and article parents must both be present before the view link")
        tabProbeTap("tabs.reselect.more.open.categories")
        XCTAssertTrue(app.staticTexts["tabs.reselect.more.destination.categories"].waitForExistence(timeout: 5))
        let roots = tabProbeRootState()
        let categoryDepth = homeNavigationReport()["categoriesPathCount"] as? Int ?? -1
        XCTAssertGreaterThanOrEqual(categoryDepth, 2,
            "The view-destination representation is observed, rather than assumed to be another typed element")
        captureTabProbe("before active Categories at view destination under category and article")
        assertTabProbeRetained(paths: ["searchPathCount": 1, "categoriesPathCount": categoryDepth, "favoritesPathCount": 1],
            rootStates: roots, player: player)
        assertTabProbeReset("Kategorier", id: "categories", path: "categoriesPathCount",
            retained: ["searchPathCount": 1, "favoritesPathCount": 1], roots: roots, player: player)
        selectHomeFixtureTab("Artikler")
        XCTAssertTrue(app.staticTexts["home.navigation.search.destination"].waitForExistence(timeout: 5))
        captureTabProbe("ordinary switch restores Search list")
        assertTabProbeRetained(paths: ["searchPathCount": 1, "categoriesPathCount": 0, "favoritesPathCount": 1],
            rootStates: roots, player: player)
    }

    func testFavoritesTabReselectionClosesArticleAuthorAndViewDestination() {
        let player = prepareTabProbe()
        tabProbeChooseRoot("Artikler", id: "search"); tabProbeOpenSearch()
        tabProbeChooseRoot("Kategorier", id: "categories"); tabProbeOpenCategory(nested: true)
        tabProbeChooseRoot("Min side", id: "favorites"); tabProbeOpenFavorite()
        tabProbeTap("tabs.reselect.author.open.favorites")
        XCTAssertTrue(app.staticTexts["tabs.reselect.author.destination"].waitForExistence(timeout: 5))
        XCTAssertEqual(homeNavigationReport()["favoritesPathCount"] as? Int, 2,
            "The real typed article and author parents must both be present before the view link")
        tabProbeTap("tabs.reselect.more.open.favorites")
        XCTAssertTrue(app.staticTexts["tabs.reselect.more.destination.favorites"].waitForExistence(timeout: 5))
        let roots = tabProbeRootState()
        let favoriteDepth = homeNavigationReport()["favoritesPathCount"] as? Int ?? -1
        XCTAssertGreaterThanOrEqual(favoriteDepth, 2)
        captureTabProbe("before active Min side at view destination under article and author")
        assertTabProbeRetained(paths: ["searchPathCount": 1, "categoriesPathCount": 2, "favoritesPathCount": favoriteDepth],
            rootStates: roots, player: player)
        assertTabProbeReset("Min side", id: "favorites", path: "favoritesPathCount",
            retained: ["searchPathCount": 1, "categoriesPathCount": 2], roots: roots, player: player)
        selectHomeFixtureTab("Artikler")
        XCTAssertTrue(app.staticTexts["home.navigation.search.destination"].waitForExistence(timeout: 5))
        captureTabProbe("ordinary switch after Min side reset retains Search")
        assertTabProbeRetained(paths: ["searchPathCount": 1, "categoriesPathCount": 2, "favoritesPathCount": 0],
            rootStates: roots, player: player)
    }

    private func heroTagsReport() -> [String: Any] {
        guard let text = status.value as? String, let marker = text.range(of: " heroGeometry="),
              let bytes = String(text[marker.upperBound...]).data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return [:] }
        return payload
    }

    func testHomeHeroTagsKeepWholeWordsAndDoNotOverlapTitleIndicatorsOrActions() {
        launch("heroTags")
        let required = ["hero-1.card", "hero-1.section", "hero-1.title.text", "hero-1.read", "hero-1.favorite", "hero-1.tags",
            "hero-1.author.text", "hero-1.author.pill", "hero-1.reference.author.0", "hero-1.reference.author.1",
            "hero-1.category.0.text", "hero-1.category.0.pill", "hero-1.reference.category.0.0",
            "hero-1.category.1.text", "hero-1.category.1.pill", "hero-1.reference.category.1.0"]
            + (1...5).map { "indicator.hero-\($0)" }
        let ready = NSPredicate { [weak self] _, _ in
            guard let self, let frames = self.heroTagsReport()["frames"] as? [String: [String: Double]] else { return false }
            return required.allSatisfy { frames[$0] != nil }
        }
        let expectation = XCTNSPredicateExpectation(predicate: ready, object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
        let report = heroTagsReport()
        let bytes = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        let geometry = XCTAttachment(string: String(decoding: bytes, as: UTF8.self))
        geometry.name = "Home hero actual tag and whole-card geometry"; geometry.lifetime = .keepAlways; add(geometry)
        capture("Home — actual complete hero and author-category capsules")
        XCTAssertEqual(report["environmentAccessibility"] as? Bool, report["systemAccessibility"] as? Bool)
        XCTAssertEqual(app.staticTexts["home.hero.author.hero-1"].label, "Signe Jensen")
        XCTAssertEqual(app.staticTexts["home.hero.category.hero-1.0"].label, "KULTUR")
        XCTAssertEqual(app.staticTexts["home.hero.category.hero-1.1"].label, "DESIGN")

        let card = compactFrame("hero-1.card", report: report)
        let group = compactFrame("hero-1.tags", report: report)
        let title = compactFrame("hero-1.title.text", report: report)
        let section = compactFrame("hero-1.section", report: report)
        let read = compactFrame("hero-1.read", report: report)
        let favorite = compactFrame("hero-1.favorite", report: report)
        var failures: [String] = []
        func require(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }
        func disjoint(_ a: CGRect, _ b: CGRect) -> Bool {
            let overlap = a.intersection(b)
            return overlap.isNull || overlap.width * overlap.height < 0.001
        }
        let author = compactFrame("hero-1.author.text", report: report)
        let authorWords = [compactFrame("hero-1.reference.author.0", report: report),
            compactFrame("hero-1.reference.author.1", report: report)]
        require(author.width + 1 >= (authorWords.map(\.width).max() ?? 0),
            "Author capsule compresses a whole same-font word into fragments")
        require(author.height <= authorWords.reduce(0) { $0 + $1.height } + 1,
            "Two author words should need no more than two natural text lines")
        var pills: [CGRect] = []
        for key in ["author", "category.0", "category.1"] {
            let text = compactFrame("hero-1." + key + ".text", report: report)
            let pill = compactFrame("hero-1." + key + ".pill", report: report)
            require(pill.insetBy(dx: -1, dy: -1).contains(text), "\(key) text exceeds its actual capsule")
            require(group.insetBy(dx: -1, dy: -1).contains(pill), "\(key) capsule exceeds the tag group")
            require(card.insetBy(dx: -1, dy: -1).contains(pill), "\(key) capsule exceeds the visible hero")
            if key != "author" {
                let word = compactFrame("hero-1.reference." + key + ".0", report: report)
                require(text.width + 1 >= word.width, "\(key) splits a short word despite enough full-row width")
                require(abs(text.height - word.height) <= 1, "\(key) must use one natural line without shrinking the font")
            }
            pills.append(pill)
        }
        for (index, pill) in pills.enumerated() {
            for previous in pills.prefix(index) { require(disjoint(pill, previous), "Hero capsules overlap") }
        }
        for (key, frame) in [("section", section), ("title", title), ("tags", group), ("read", read), ("favorite", favorite)] {
            require(card.insetBy(dx: -1, dy: -1).contains(frame), "\(key) exceeds the clipped hero card")
        }
        require(disjoint(title, group), "Title overlaps the author/category capsules")
        require(disjoint(group, read) && disjoint(group, favorite), "Tags overlap the real article actions")
        require(disjoint(read, favorite), "Read and favorite buttons overlap")
        for index in 1...5 {
            let dot = compactFrame("indicator.hero-\(index)", report: report)
            require(card.insetBy(dx: -1, dy: -1).contains(dot), "Carousel dot exceeds the hero card")
            require(disjoint(dot, read) && disjoint(dot, favorite), "Carousel dot overlaps the read/favorite action")
            require(disjoint(dot, group) && disjoint(dot, title), "Carousel dot overlaps editorial text")
        }
        let checks = XCTAttachment(string: failures.isEmpty ? "All whole-word and whole-card checks passed" : failures.joined(separator: "\n"))
        checks.name = "Home hero visual geometry checks"; checks.lifetime = .keepAlways; add(checks)
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
        XCTAssertEqual(card.minY, app.frame.minY, accuracy: 1, "The actual edge fixture still reaches the screen top")

        let favoriteAction = app.buttons["home.hero.favorite.hero-1"]
        XCTAssertTrue(favoriteAction.isHittable); favoriteAction.tap()
        waitStatus(["favorites=1", "firebase=off", "played=0"])
        XCTAssertEqual(favoriteAction.label, "Fjern fra gemte artikler")
        let readAction = app.buttons["home.hero.read.hero-1"]
        XCTAssertTrue(readAction.isHittable); readAction.tap()
        let opened = app.staticTexts["home.fixture.openedArticle"]
        XCTAssertTrue(opened.waitForExistence(timeout: 5)); XCTAssertEqual(opened.label, "Fra redaktionen 1")
        waitStatus(["opened=1", "firebase=off", "played=0"])
    }


    private func listNavigationReport() -> [String: Any] {
        guard let value = app.staticTexts["list.navigation.state"].value as? String,
              let bytes = value.data(using: .utf8),
              let report = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return [:] }
        return report
    }
    private func listFrame(_ key: String, report: [String: Any]) -> CGRect {
        guard let frame = report[key] as? [String: Double] else { return .zero }
        return CGRect(x: frame["x"] ?? 0, y: frame["y"] ?? 0,
            width: frame["width"] ?? 0, height: frame["height"] ?? 0)
    }
    private func actualListRow(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }
    private func listScroller() -> XCUIElement {
        let detail = listFrame("detailFrame", report: listNavigationReport())
        XCTAssertFalse(detail.isEmpty, "Require the actual current detail-host geometry")
        guard let scroll = app.scrollViews.allElementsBoundByIndex.first(where: {
            let frame = $0.frame
            return $0.isHittable && frame.width > detail.width * 0.5
                && frame.intersection(detail).width >= frame.width * 0.95
        }) else {
            XCTFail("No visible scroller in the current detail pane")
            return app.scrollViews["missing-detail-scroller"]
        }
        return scroll
    }
    private func listNavigationBar() -> XCUIElement? {
        let detail = listFrame("detailFrame", report: listNavigationReport())
        XCTAssertFalse(detail.isEmpty, "Require the actual current detail-host geometry")
        return app.navigationBars.allElementsBoundByIndex.first(where: {
            let frame = $0.frame
            return $0.isHittable && frame.width > detail.width * 0.5
                && frame.intersection(detail).width >= frame.width * 0.95
        })
    }
    private func listUsableBounds() -> CGRect {
        let scroll = listScroller().frame.intersection(app.frame)
        let nav = listNavigationBar()
        // Full visibility starts at the actual viewport/navigation edge, not
        // an extra margin that a field at the settled scroll top cannot reach.
        let top = max(scroll.minY, nav?.frame.maxY ?? scroll.minY)
        let report = listNavigationReport()
        let mini = listFrame("miniFrame", report: report)
        let bottom: CGFloat
        if report["hasActiveEpisode"] as? Bool == true {
            bottom = min(scroll.maxY - 8, mini.isEmpty ? scroll.maxY - 8 : mini.minY - 8)
        } else {
            // Once dismissed, stale player geometry grants no obstruction. Use
            // the actual viewport and only a tab bar placed at the screen bottom.
            let key = report["selectedTab"] as? String == "Kategorier" ? "categoryViewport" : "searchViewport"
            let viewport = listFrame(key, report: report)
            var unobstructedBottom = min(scroll.maxY, viewport.isEmpty ? scroll.maxY : viewport.maxY)
            let tabBar = app.tabBars.firstMatch
            if tabBar.exists, tabBar.frame.midY > app.frame.midY {
                unobstructedBottom = min(unobstructedBottom, tabBar.frame.minY)
            }
            bottom = unobstructedBottom
        }
        return CGRect(x: scroll.minX, y: top, width: scroll.width, height: max(1, bottom - top))
    }
    @discardableResult
    private func revealListItemAboveMini(_ item: XCUIElement, maxDrags: Int = 32, towardEnd: Bool = true,
                                         file: StaticString = #filePath, line: UInt = #line) -> Bool {
        XCTAssertTrue(listScroller().waitForExistence(timeout: 5), file: file, line: line)
        for _ in 0..<maxDrags {
            let bounds = listUsableBounds()
            var down = towardEnd
            var edgeDistance: CGFloat?
            if item.exists {
                let frame = item.frame
                if !frame.isEmpty, bounds.insetBy(dx: -1, dy: -1).contains(frame), item.isHittable { return true }
                if frame.minY < bounds.minY { down = false; edgeDistance = bounds.minY - frame.minY + 12 }
                else if frame.maxY > bounds.maxY { down = true; edgeDistance = frame.maxY - bounds.maxY + 12 }
            }
            let distance = min(min(340, bounds.height * 0.65), edgeDistance ?? .greatestFiniteMagnitude)
            let startY = bounds.midY + (down ? distance / 2 : -distance / 2)
            let endY = bounds.midY + (down ? -distance / 2 : distance / 2)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: bounds.midX, dy: startY)).press(forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: bounds.midX, dy: endY)))
        }
        // The final bounded drag can be the one that reveals the target.
        // Inspect its settled result with exactly the same full-frame condition.
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard item.exists else { return false }
            let frame = item.frame
            return !frame.isEmpty && self.listUsableBounds().insetBy(dx: -1, dy: -1).contains(frame) && item.isHittable
        }, object: item)
        return XCTWaiter.wait(for: [settled], timeout: 2) == .completed
    }
    private func captureListNavigation(_ phase: String, details: [String: Any] = [:]) {
        let diagnostics = app.descendants(matching: .any).matching(identifier: "list.navigation.diagnostics").firstMatch
        let dynamicValue = diagnostics.exists ? diagnostics.value as? String ?? "{\"valueMissing\":true}" : "{\"probeMissing\":true}"
        let uiKit = XCTAttachment(string: dynamicValue)
        uiKit.name = "Actual UIKit list geometry — " + phase; uiKit.lifetime = .keepAlways; add(uiKit)
        var report = listNavigationReport()
        report["details"] = details
        report["usableBounds"] = rectanglePayload(listUsableBounds())
        if let bytes = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            let attachment = XCTAttachment(string: String(decoding: bytes, as: UTF8.self))
            attachment.name = "Actual list navigation — " + phase; attachment.lifetime = .keepAlways; add(attachment)
        }
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "List hierarchy — " + phase; hierarchy.lifetime = .keepAlways; add(hierarchy)
        capture("Lists and mini-player — " + phase)
    }
    private func rectanglePayload(_ rect: CGRect) -> [String: Double] {
        ["x": Double(rect.minX), "y": Double(rect.minY), "width": Double(rect.width), "height": Double(rect.height)]
    }
    private func tapVisibleListRowAtOriginalFrame(_ row: XCUIElement, original: CGRect, phase: String,
        file: StaticString = #filePath, line: UInt = #line) {
        let current = row.exists ? row.frame : .zero
        captureListNavigation(phase, details: ["rowBefore": rectanglePayload(original),
            "rowImmediatelyBeforeTouch": rectanglePayload(current), "hittable": row.exists && row.isHittable])
        XCTAssertTrue(row.exists, file: file, line: line)
        XCTAssertTrue(row.isHittable, "The actual row remains hittable before its ordinary tap", file: file, line: line)
        let frame = row.frame
        XCTAssertTrue(listUsableBounds().insetBy(dx: -1, dy: -1).contains(frame),
            "The whole row remains above the mini-player immediately before touch", file: file, line: line)
        XCTAssertEqual(frame.minX, original.minX, accuracy: 1, file: file, line: line)
        XCTAssertEqual(frame.minY, original.minY, accuracy: 1, file: file, line: line)
        XCTAssertEqual(frame.width, original.width, accuracy: 1, file: file, line: line)
        XCTAssertEqual(frame.height, original.height, accuracy: 1, file: file, line: line)
        row.tap()
    }

    private func tapActualListBack(file: StaticString = #filePath, line: UInt = #line) {
        guard let bar = listNavigationBar() else {
            XCTFail("No current detail navigation bar", file: file, line: line); return
        }
        let back = bar.buttons["BackButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Use the native back button, never a fixture pop action", file: file, line: line)
        XCTAssertTrue(back.isHittable, file: file, line: line); back.tap()
    }
    private func assertMiniPlacementMatchesRoot(file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            guard let self, let expected = self.listNavigationReport()["expectedMiniTop"] as? Double,
                  let rootBottom = self.listNavigationReport()["rootBottom"] as? Double, rootBottom > 0 else { return false }
            let actual = self.listFrame("miniFrame", report: self.listNavigationReport())
            return actual.height > 0 && abs(actual.minY - expected) <= 1
        }, object: app.staticTexts["list.navigation.state"])
        let result = XCTWaiter.wait(for: [ready], timeout: 5)
        if result != .completed { captureListNavigation("root mini-top mismatch") }
        XCTAssertEqual(result, .completed, "The root's predicted player edge must match the actual visible mini-player", file: file, line: line)
    }

    private func assertMiniPauseDoesNotNavigate(file: StaticString = #filePath, line: UInt = #line) {
        let before = listNavigationReport()
        let pause = app.buttons["podcast.mini.playPause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(pause.label, "Pause", file: file, line: line)
        XCTAssertTrue(pause.isHittable, file: file, line: line); pause.tap()
        XCTAssertEqual(pause.label, "Afspil", file: file, line: line)
        let after = listNavigationReport()
        XCTAssertEqual(after["pauseActions"] as? Int, 1, file: file, line: line)
        XCTAssertEqual(after["openActions"] as? Int, 0, file: file, line: line)
        XCTAssertEqual(after["searchPathCount"] as? Int, before["searchPathCount"] as? Int, file: file, line: line)
        XCTAssertEqual(after["categoriesPathCount"] as? Int, before["categoriesPathCount"] as? Int, file: file, line: line)
        XCTAssertEqual(after["firebaseStarted"] as? Bool, false, file: file, line: line)
    }

    func testIPadCategoryPrimaryRowEmptyCenterOpensAndReturnsWithMiniPlayer() throws {
        launch("listNavigation")
        try XCTSkipIf(app.frame.width < 600, "This focused blank-centre probe requires the iPad row layout")
        let category = app.buttons["Film"]
        XCTAssertTrue(category.isHittable); category.tap()
        let row = actualListRow("Kun film")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(revealListItemAboveMini(row))
        XCTAssertEqual(listNavigationReport()["categoriesPathCount"] as? Int, 1)
        XCTAssertEqual(listNavigationReport()["searchPathCount"] as? Int, 0)
        XCTAssertEqual(listNavigationBar()?.identifier, "Film")
        assertMiniPlacementMatchesRoot()

        let original = row.frame
        let centre = CGPoint(x: original.midX, y: original.midY)
        let labels = row.staticTexts.allElementsBoundByIndex.filter { !$0.label.isEmpty && !$0.frame.isEmpty }
        let textEvidence: [[String: Any]] = labels.map {
            ["label": $0.label, "frame": rectanglePayload($0.frame)]
        }
        captureListNavigation("iPad primary category row has an empty centre", details: [
            "rowBefore": rectanglePayload(original), "rowCentre": ["x": centre.x, "y": centre.y],
            "textFrames": textEvidence,
            "centreInsideAnyTextFrame": labels.contains { $0.frame.contains(centre) }
        ])
        XCTAssertTrue(labels.contains { $0.label == "Kun film" })
        XCTAssertTrue(labels.contains { $0.label == "Denne artikel tilhører kun Film." })
        XCTAssertFalse(labels.contains { $0.frame.insetBy(dx: -1, dy: -1).contains(centre) },
            "The ordinary row centre must actually lie outside its visible text frames")
        let lastTextEdge = try XCTUnwrap(labels.map { $0.frame.maxX }.max())
        XCTAssertGreaterThan(centre.x - lastTextEdge, 12,
            "Use the real blank middle of the wide row, not a point over the title or subtitle")
        XCTAssertTrue(listUsableBounds().insetBy(dx: -1, dy: -1).contains(original))
        assertMiniPauseDoesNotNavigate()

        // This helper uses ordinary row.tap(). There is no title tap or
        // coordinate workaround; its original-frame guards remain intact.
        tapVisibleListRowAtOriginalFrame(row, original: original,
            phase: "iPad short primary row immediately before ordinary tap")
        let article = app.staticTexts["list.navigation.article"]
        let arrived = article.waitForExistence(timeout: 5)
        // The local article destination is Text, not a ScrollView. Preserve
        // the entry evidence without asking a departed list for its viewport.
        var destinationReport = listNavigationReport()
        destinationReport["details"] = [
            "rowBefore": rectanglePayload(original), "articleArrived": arrived,
            "textFramesBefore": textEvidence
        ]
        let destinationBytes = try JSONSerialization.data(withJSONObject: destinationReport, options: [.prettyPrinted, .sortedKeys])
        let destinationEvidence = XCTAttachment(string: String(decoding: destinationBytes, as: UTF8.self))
        destinationEvidence.name = "Actual list navigation — iPad primary category row after ordinary tap"
        destinationEvidence.lifetime = .keepAlways; add(destinationEvidence)
        capture("Lists and mini-player — iPad primary category row after ordinary tap")
        XCTAssertTrue(arrived, "The blank centre of the real category row opens its article")
        XCTAssertEqual(article.label, "Kun film")
        XCTAssertEqual(listNavigationReport()["openedArticleID"] as? String, "film-only")
        XCTAssertEqual(listNavigationReport()["categoriesPathCount"] as? Int, 2)
        XCTAssertTrue(app.buttons["podcast.mini.playPause"].exists)
        tapActualListBack()
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            row.exists && row.isHittable && abs(row.frame.minY - original.minY) <= 1
        }, object: row)
        let result = XCTWaiter.wait(for: [returned], timeout: 8)
        captureListNavigation("iPad primary category row after native Back", details: [
            "rowBefore": rectanglePayload(original), "rowAfter": rectanglePayload(row.exists ? row.frame : .zero)
        ])
        XCTAssertEqual(result, .completed, "Native Back keeps the row at its original position without fixture scrolling")
        XCTAssertTrue(listUsableBounds().insetBy(dx: -1, dy: -1).contains(row.frame))
        XCTAssertEqual(listNavigationReport()["categoriesPathCount"] as? Int, 1)
        XCTAssertEqual(listNavigationReport()["searchPathCount"] as? Int, 0)
        XCTAssertEqual(listNavigationReport()["hasActiveEpisode"] as? Bool, true)
        XCTAssertEqual(listNavigationReport()["pauseActions"] as? Int, 1)
        XCTAssertEqual(listNavigationReport()["openActions"] as? Int, 0)
        XCTAssertEqual(listNavigationReport()["firebaseStarted"] as? Bool, false)
        XCTAssertEqual(listNavigationBar()?.identifier, "Film")
        assertMiniPlacementMatchesRoot()
        waitStatus(["firebase=off", "played=0"])
    }

    func testCategoryIncludesSecondaryTopicsAndReturnsAboveMiniPlayer() {
        launch("listNavigation")
        app.buttons["Kultur"].tap()
        let primary = actualListRow("Kulturfortælling 1")
        XCTAssertTrue(primary.waitForExistence(timeout: 5), "A primary topic article remains in the category")
        XCTAssertEqual(listNavigationReport()["categoriesPathCount"] as? Int, 1)
        assertMiniPlacementMatchesRoot()
        let secondary = actualListRow("Film i kulturen")
        let revealed = revealListItemAboveMini(secondary, maxDrags: 12)
        captureListNavigation("Kultur includes primary and secondary topics", details: [
            "secondaryExists": secondary.exists, "secondaryFullyVisible": revealed,
            "secondaryFrame": rectanglePayload(secondary.exists ? secondary.frame : .zero),
            "unrelatedVisible": actualListRow("Kun film").exists
        ])
        XCTAssertTrue(revealed, "The actual routed category must include an article whose secondary topic is Kultur")
        XCTAssertFalse(actualListRow("Kun film").exists, "The unrelated Film-only article stays excluded")
        let original = secondary.frame
        XCTAssertLessThanOrEqual(original.maxY, listFrame("miniFrame", report: listNavigationReport()).minY - 7)
        assertMiniPauseDoesNotNavigate()
        tapVisibleListRowAtOriginalFrame(secondary, original: original,
            phase: "Kultur row immediately before ordinary tap")
        let article = app.staticTexts["list.navigation.article"]
        XCTAssertTrue(article.waitForExistence(timeout: 5)); XCTAssertEqual(article.label, "Film i kulturen")
        XCTAssertEqual(listNavigationReport()["categoriesPathCount"] as? Int, 2)
        XCTAssertTrue(app.buttons["podcast.mini.playPause"].exists)
        tapActualListBack()
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            secondary.exists && secondary.isHittable && abs(secondary.frame.minY - original.minY) <= 1
        }, object: secondary)
        let result = XCTWaiter.wait(for: [returned], timeout: 8)
        captureListNavigation("Kultur after actual article back", details: ["rowBefore": rectanglePayload(original),
            "rowAfter": rectanglePayload(secondary.exists ? secondary.frame : .zero)])
        XCTAssertEqual(result, .completed, "Back keeps the actual category list at the same visible row without fixture scrolling")
        XCTAssertEqual(listNavigationReport()["categoriesPathCount"] as? Int, 1)
        XCTAssertEqual(listNavigationReport()["searchPathCount"] as? Int, 0)
        XCTAssertEqual(listNavigationBar()?.identifier, "Kultur")

        // Exercise the actual downward-dismiss gesture only after the unchanged
        // native Back-position checks have completed.
        let activeReport = listNavigationReport()
        let formerMini = listFrame("miniFrame", report: activeReport)
        let surface = app.descendants(matching: .any).matching(identifier: "podcast.mini.surface").firstMatch
        XCTAssertTrue(surface.exists)
        XCTAssertFalse(formerMini.isEmpty)
        XCTAssertTrue(app.frame.contains(formerMini), "The measured player surface is fully visible")
        XCTAssertTrue(app.buttons["podcast.mini.playPause"].isHittable)
        XCTAssertTrue(app.buttons["podcast.mini.forward"].isHittable)
        captureListNavigation("category before actual mini dismissal", details: [
            "formerMini": rectanglePayload(formerMini), "lastRow": rectanglePayload(secondary.frame)])
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let appOrigin = app.frame.origin
        origin.withOffset(CGVector(dx: formerMini.midX - appOrigin.x, dy: formerMini.midY - appOrigin.y))
            .press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(
                dx: formerMini.midX - appOrigin.x, dy: formerMini.midY + 90 - appOrigin.y)))
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.listNavigationReport()["hasActiveEpisode"] as? Bool == false && !surface.exists
        }, object: surface)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 8), .completed)
        XCTAssertFalse(app.buttons["podcast.mini.playPause"].exists)
        XCTAssertEqual(listNavigationReport()["hasActiveEpisode"] as? Bool, false)
        XCTAssertEqual(listNavigationReport()["openActions"] as? Int, 0)
        XCTAssertEqual(listNavigationReport()["categoriesPathCount"] as? Int, activeReport["categoriesPathCount"] as? Int)
        XCTAssertEqual(listNavigationReport()["searchPathCount"] as? Int, activeReport["searchPathCount"] as? Int)

        // A bounded additional endward drag must settle at the same final-row
        // position: this verifies the real scroll end, not a transient overscroll.
        var settledAtEnd = false
        for _ in 0..<4 {
            let beforeDrag = secondary.frame
            let bounds = listUsableBounds()
            let distance = min(340, bounds.height * 0.65)
            origin.withOffset(CGVector(dx: bounds.midX - appOrigin.x, dy: bounds.midY + distance / 2 - appOrigin.y))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(
                    dx: bounds.midX - appOrigin.x, dy: bounds.midY - distance / 2 - appOrigin.y)))
            var previous = CGRect.null
            var stableSince = ProcessInfo.processInfo.systemUptime
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard secondary.exists else { return false }
                let frame = secondary.frame
                if previous.isNull || abs(frame.minY - previous.minY) > 0.1 {
                    previous = frame; stableSince = ProcessInfo.processInfo.systemUptime
                    return false
                }
                return ProcessInfo.processInfo.systemUptime - stableSince >= 0.4
                    && secondary.isHittable && self.listUsableBounds().insetBy(dx: -1, dy: -1).contains(frame)
            }, object: secondary)
            if XCTWaiter.wait(for: [settled], timeout: 5) == .completed,
                abs(secondary.frame.minY - beforeDrag.minY) <= 1 {
                settledAtEnd = true; break
            }
        }
        let releasedRow = secondary.frame
        captureListNavigation("category at settled end after mini dismissal", details: [
            "formerMini": rectanglePayload(formerMini), "lastRow": rectanglePayload(releasedRow),
            "settledAtEnd": settledAtEnd, "unobstructedViewport": rectanglePayload(listUsableBounds())])
        XCTAssertTrue(settledAtEnd, "The last row settles at the actual scroll end after dismissal")
        XCTAssertTrue(secondary.isHittable)
        XCTAssertTrue(listUsableBounds().insetBy(dx: -1, dy: -1).contains(releasedRow))
        XCTAssertGreaterThan(releasedRow.maxY, formerMini.maxY,
            "The last row uses space beyond the former mini-player's lower edge")
        XCTAssertEqual(listNavigationReport()["openActions"] as? Int, 0)
        XCTAssertEqual(listNavigationReport()["categoriesPathCount"] as? Int, 1)
        XCTAssertEqual(listNavigationReport()["searchPathCount"] as? Int, 0)
        waitStatus(["firebase=off", "played=0"])
    }

    func testSearchRestoresLoadedResultsAndScrollPositionWithMiniPlayer() {
        launch("listNavigation")
        let tabBarItem = app.tabBars.buttons["Artikler"]
        let sidebarItem = app.buttons["ipad.navigation.search"]
        if sidebarItem.exists {
            XCTAssertTrue(sidebarItem.isHittable); sidebarItem.tap()
        } else if tabBarItem.exists {
            XCTAssertTrue(tabBarItem.isHittable); tabBarItem.tap()
        } else {
            // iPad's real floating tab uses Cell/Other modern AX types, despite
            // its legacy Button description, and has no TabBar ancestor.
            let floatingItems = app.descendants(matching: .any).matching(NSPredicate(
                format: "identifier == %@ AND label == %@", "doc.text", "Artikler"))
            let floatingItem = floatingItems.allElementsBoundByIndex.first(where: { $0.isHittable })
            XCTAssertNotNil(floatingItem, "Use the actual visible iPad system tab")
            floatingItem?.tap()
        }
        let toggle = app.buttons["search.controls.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let closedToggleLabel = toggle.label
        toggle.tap()
        let query = app.textFields["search.controls.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5)); query.tap(); query.typeText("Rejse\n")
        let keyboardGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardGone], timeout: 5), .completed)
        let sort = app.buttons["search.controls.sort"]
        XCTAssertTrue(sort.isHittable); sort.tap()
        let titleSort = app.buttons["Titel A-Å"].firstMatch
        XCTAssertTrue(titleSort.waitForExistence(timeout: 5)); titleSort.tap()
        XCTAssertTrue(app.staticTexts["40 artikler"].waitForExistence(timeout: 8))
        let clear = app.buttons["search.controls.clear"]
        let count = app.staticTexts["search.controls.count"]
        let initialControls: [String: Any] = ["query": query.value as? String ?? "", "sortLabel": sort.label,
            "sortValue": sort.value as? String ?? "", "closedToggleLabel": closedToggleLabel,
            "toggle": rectanglePayload(toggle.frame), "sort": rectanglePayload(sort.frame),
            "clear": rectanglePayload(clear.frame), "toggleLabel": toggle.label, "clearLabel": clear.label,
            "count": rectanglePayload(count.exists ? count.frame : .zero), "countLabel": count.exists ? count.label : ""]
        var failures: [String] = []
        if sort.label != "Sortér artikler" || sort.value as? String != "Titel A-Å" {
            failures.append("Actual sort name/value must expose Sortér artikler / Titel A-Å")
        }
        if closedToggleLabel != "Vis søgning" || toggle.label != "Luk søgning" || clear.label != "Ryd søgning" {
            failures.append("Search toggle and clear must have their explicit Danish action labels")
        }
        for (name, control) in [("search", toggle), ("sort", sort), ("clear", clear)] {
            if control.frame.width + 0.001 < 44 || control.frame.height + 0.001 < 44 {
                failures.append("\(name) actual target is below44pt: \(control.frame)")
            }
        }
        for (name, control) in [("sort", sort), ("count", count)] {
            if !control.exists || control.frame.isEmpty
                || !listUsableBounds().insetBy(dx: -1, dy: -1).contains(control.frame) {
                failures.append("The full \(name) control must remain inside the visible viewport above the player")
            }
        }
        captureListNavigation("query and sort before deep article", details: initialControls)
        assertMiniPlacementMatchesRoot()
        let more = app.buttons["Indlæs flere artikler"]
        let moreRevealed = revealListItemAboveMini(more)
        captureListNavigation("settled load-more above mini-player", details: ["fullyVisible": moreRevealed,
            "buttonFrame": rectanglePayload(more.exists ? more.frame : .zero)])
        XCTAssertTrue(moreRevealed, "The real load-more button can be reached above the mini-player")
        more.tap()
        let finalRow = actualListRow("Rejse 40")
        let finalRevealed = revealListItemAboveMini(finalRow)
        if !finalRevealed {
            captureListNavigation("last-result discovery failed", details: ["fullyVisible": false,
                "rowFrame": rectanglePayload(finalRow.exists ? finalRow.frame : .zero)])
        }
        XCTAssertTrue(finalRevealed, "The last loaded result must be wholly visible and tappable above the mini-player")
        XCTAssertFalse(more.exists, "All40 query results were loaded through the real button")
        let original = finalRow.frame
        assertMiniPauseDoesNotNavigate()
        captureListNavigation("last query result above the mini-player", details: ["rowBefore": rectanglePayload(original)])
        tapVisibleListRowAtOriginalFrame(finalRow, original: original,
            phase: "Search row immediately before ordinary tap")
        let article = app.staticTexts["list.navigation.article"]
        XCTAssertTrue(article.waitForExistence(timeout: 5)); XCTAssertEqual(article.label, "Rejse 40")
        XCTAssertEqual(listNavigationReport()["searchPathCount"] as? Int, 1)
        tapActualListBack()
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            finalRow.exists && finalRow.isHittable && abs(finalRow.frame.minY - original.minY) <= 1 && !more.exists
        }, object: finalRow)
        let result = XCTWaiter.wait(for: [returned], timeout: 8)
        captureListNavigation("search after actual article back", details: ["rowBefore": rectanglePayload(original),
            "rowAfter": rectanglePayload(finalRow.exists ? finalRow.frame : .zero), "controlsBefore": initialControls])
        if result != .completed { failures.append("Actual search return changed the loaded last row or its visible position") }
        XCTAssertEqual(listNavigationReport()["searchPathCount"] as? Int, 0)
        XCTAssertEqual(listNavigationReport()["categoriesPathCount"] as? Int, 0)
        // Only after recording the untouched returned position, scroll to the
        // actual controls and check retained query and chosen sort.
        XCTAssertTrue(revealListItemAboveMini(query, maxDrags: 40, towardEnd: false))
        XCTAssertEqual(query.value as? String, "Rejse")
        XCTAssertEqual(sort.label, "Sortér artikler")
        XCTAssertEqual(sort.value as? String, "Titel A-Å", "The actual selected sort remains unchanged")
        XCTAssertTrue(app.staticTexts["40 artikler"].exists)
        captureListNavigation("retained query and sort", details: ["query": query.value as? String ?? "",
            "sortLabel": sort.label, "sortValue": sort.value as? String ?? ""])
        let checks = XCTAttachment(string: failures.isEmpty ? "All list-return and44pt target checks passed" : failures.joined(separator: "\n"))
        checks.name = "Actual search-return checks"; checks.lifetime = .keepAlways; add(checks)
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
        waitStatus(["firebase=off", "played=0"])
    }

}
