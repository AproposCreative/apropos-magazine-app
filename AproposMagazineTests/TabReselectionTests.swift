import Combine
import Foundation
import SwiftUI
import XCTest
@testable import Apropos

private typealias AppTab = Apropos.Tab

// Every coordinator explicitly disables the incoming-link observer.
// Paths never start the app service runtime. Native tests cover the shared shell.
@MainActor
final class TabReselectionTests: XCTestCase {
    func testReselectEachActiveTabClearsOnlyItsHeterogeneousStack() throws {
        for active in AppTab.allCases {
            let navigation = populatedNavigation()
            navigation.selectedTab = active
            let before = try snapshots(navigation)

            navigation.reselect(active)

            XCTAssertEqual(navigation.selectedTab, active)
            XCTAssertTrue(navigation.path(for: active).wrappedValue.isEmpty)
            try assertOtherStacksUnchanged(navigation, except: active, before: before)
        }
    }

    func testHomeReselectRenewsHomeIdentityAndScrollsEvenWhenItsPathIsAlreadyRoot() throws {
        let navigation = populatedNavigation()
        navigation.selectedTab = .home
        let before = try snapshots(navigation)
        let probe = Probe()
        let scroll = NotificationCenter.default.publisher(for: .scrollHomeToTop).sink { _ in
            MainActor.assumeIsolated { probe.scrolls += 1 }
        }
        defer { scroll.cancel() }
        let originalID = navigation.homeStackID

        navigation.reselect(.home)

        XCTAssertTrue(navigation.homePath.isEmpty)
        XCTAssertNotEqual(navigation.homeStackID, originalID)
        XCTAssertEqual(probe.scrolls, 1)
        try assertOtherStacksUnchanged(navigation, except: .home, before: before)

        // Home also owns destinations outside NavigationPath. Its established
        // identity/scroll reset is intentionally different from other root tabs.
        let rootID = navigation.homeStackID
        navigation.reselect(.home)
        XCTAssertNotEqual(navigation.homeStackID, rootID)
        XCTAssertEqual(probe.scrolls, 2)
        try assertOtherStacksUnchanged(navigation, except: .home, before: before)
    }

    func testRepeatedNonHomeRootReselectIsSilentAndPreservesEveryStack() throws {
        for active in [AppTab.search, .categories, .favorites] {
            let navigation = populatedNavigation()
            navigation.selectedTab = active
            navigation.reselect(active)
            let rootSnapshot = try snapshots(navigation)
            let homeID = navigation.homeStackID
            let probe = Probe()
            let observation = navigation.objectWillChange.sink { _ in
                MainActor.assumeIsolated { probe.publications += 1 }
            }
            defer { observation.cancel() }

            navigation.reselect(active)
            navigation.reselect(active)

            XCTAssertEqual(probe.publications, 0, "A root no-op must not publish a replacement path/selection")
            XCTAssertEqual(try snapshots(navigation), rootSnapshot)
            XCTAssertEqual(navigation.homeStackID, homeID)
            XCTAssertEqual(navigation.selectedTab, active)
        }
    }

    func testOrdinaryNavigationPreservesNonHomeStacksAndExistingHomeResetPolicy() throws {
        let navigation = populatedNavigation()
        let before = try snapshots(navigation)
        let homeID = navigation.homeStackID

        for destination in [AppTab.search, .categories, .favorites] {
            navigation.navigateToTab(destination)
            XCTAssertEqual(navigation.selectedTab, destination)
            XCTAssertEqual(try snapshots(navigation), before)
            XCTAssertEqual(navigation.homeStackID, homeID)
        }

        navigation.navigateToTab(.home)
        XCTAssertEqual(navigation.selectedTab, .home)
        XCTAssertTrue(navigation.homePath.isEmpty)
        XCTAssertNotEqual(navigation.homeStackID, homeID)
        try assertOtherStacksUnchanged(navigation, except: .home, before: before)
    }

    func testStaleModelReselectTargetDoesNotPublishSelectOrClearAnything() throws {
        let navigation = populatedNavigation()
        navigation.selectedTab = .categories
        let before = try snapshots(navigation)
        let homeID = navigation.homeStackID
        let probe = Probe()
        let observation = navigation.objectWillChange.sink { _ in
            MainActor.assumeIsolated { probe.publications += 1 }
        }
        defer { observation.cancel() }

        for stale in [AppTab.home, .search, .favorites] {
            navigation.reselect(stale)
        }

        XCTAssertEqual(navigation.selectedTab, .categories)
        XCTAssertEqual(try snapshots(navigation), before)
        XCTAssertEqual(navigation.homeStackID, homeID)
        XCTAssertEqual(probe.publications, 0)
    }

    private func populatedNavigation() -> NavigationCoordinator {
        let navigation = NavigationCoordinator(observeIncomingArticleLinks: false)
        for (index, tab) in AppTab.allCases.enumerated() {
            let article = Article(id: String(format: "%024x", index + 1),
                name: "Lokal \(tab.rawValue)", slug: "local-tab-\(index)", content: "<p>Local only.</p>",
                intro: "Local navigation fixture", topicID: "local-topic")
            navigation.navigateToArticle(article, in: tab)
            navigation.navigateToCategory("Lokal kategori \(index)", in: tab)
        }
        return navigation
    }

    private func snapshots(_ navigation: NavigationCoordinator) throws -> [[Data]] {
        try AppTab.allCases.map { tab in
            let path = navigation.path(for: tab).wrappedValue
            let representation = try XCTUnwrap(path.codable)
            let encoded = try JSONEncoder().encode(representation)
            let entries = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String])
            // Compare complete public CodableRepresentation values, not counts.
            // Canonicalize the nested encoded objects only, so JSON key order
            // cannot make an unchanged heterogeneous path appear different.
            return try entries.map { entry in
                let bytes = Data(entry.utf8)
                if entry.first == "{" || entry.first == "[",
                   let object = try? JSONSerialization.jsonObject(with: bytes) {
                    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
                }
                return bytes
            }
        }
    }

    private func assertOtherStacksUnchanged(_ navigation: NavigationCoordinator, except active: AppTab,
                                           before: [[Data]], file: StaticString = #filePath, line: UInt = #line) throws {
        let after = try snapshots(navigation)
        for (index, tab) in AppTab.allCases.enumerated() where tab != active {
            XCTAssertEqual(after[index], before[index], "Unrelated \(tab.rawValue) stack changed", file: file, line: line)
        }
    }

    @MainActor
    private final class Probe {
        var publications = 0
        var scrolls = 0
    }
}
