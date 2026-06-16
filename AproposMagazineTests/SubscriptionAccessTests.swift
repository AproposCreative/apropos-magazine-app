import XCTest
@testable import Apropos_Magazine

final class SubscriptionAccessTests: XCTestCase {
  private func sampleArticle(isPremium: Bool?) -> Article {
    Article(
      id: "article-1",
      name: "Test",
      slug: "test",
      content: "<p>Body</p>",
      intro: "Intro",
      topicID: "topic",
      isPremium: isPremium
    )
  }

  func testFreeArticleAlwaysReadableWhenSubscriptionsDisabled() {
    let article = sampleArticle(isPremium: true)
    XCTAssertTrue(
      ArticleAccessPolicy.canReadFullContent(article: article, isSubscribed: false)
    )
  }

  func testPremiumArticleRequiresSubscriptionWhenEnabled() {
    let defaults = UserDefaults.standard
    let key = "subscriptions_enabled"
    let previous = defaults.object(forKey: key)
    defaults.set(true, forKey: key)
    defer {
      if let previous {
        defaults.set(previous, forKey: key)
      } else {
        defaults.removeObject(forKey: key)
      }
    }

    let premium = sampleArticle(isPremium: true)
    let free = sampleArticle(isPremium: false)

    XCTAssertFalse(
      ArticleAccessPolicy.canReadFullContent(article: premium, isSubscribed: false)
    )
    XCTAssertTrue(
      ArticleAccessPolicy.canReadFullContent(article: free, isSubscribed: false)
    )
    XCTAssertTrue(
      ArticleAccessPolicy.canReadFullContent(article: premium, isSubscribed: true)
    )
  }
}
