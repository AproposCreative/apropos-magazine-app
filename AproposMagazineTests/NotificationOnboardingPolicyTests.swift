import XCTest
@testable import Apropos

final class NotificationOnboardingPolicyTests: XCTestCase {
    func testDecliningAfterSelectingTopicsLeavesEveryPushPreferenceDisabled() {
        let choices = NotificationOnboardingPolicy.choices(
            allowNotifications: false,
            selectedCategoryIds: ["music", "film"]
        )

        XCTAssertTrue(choices.selectedCategoryIds.isEmpty)
        XCTAssertFalse(choices.preferences.newArticles)
        XCTAssertFalse(choices.preferences.newPodcasts)
        XCTAssertFalse(choices.preferences.festivalReminders)
        XCTAssertFalse(choices.preferences.breakingNews)
        XCTAssertFalse(choices.preferences.weeklyDigest)
    }

    func testAllowingAllTopicsEnablesGeneralArticleAndPodcastPush() {
        let choices = NotificationOnboardingPolicy.choices(
            allowNotifications: true,
            selectedCategoryIds: []
        )

        XCTAssertTrue(choices.selectedCategoryIds.isEmpty)
        XCTAssertTrue(choices.preferences.newArticles)
        XCTAssertTrue(choices.preferences.newPodcasts)
    }

    func testAllowingSelectedTopicsKeepsSelectionWithoutGeneralArticlePush() {
        let choices = NotificationOnboardingPolicy.choices(
            allowNotifications: true,
            selectedCategoryIds: ["music", "film"]
        )

        XCTAssertEqual(choices.selectedCategoryIds, ["music", "film"])
        XCTAssertFalse(choices.preferences.newArticles)
        XCTAssertTrue(choices.preferences.newPodcasts)
    }
}
