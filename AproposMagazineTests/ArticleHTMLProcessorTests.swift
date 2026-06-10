import XCTest
@testable import Apropos_Magazine

final class ArticleHTMLProcessorTests: XCTestCase {
    func testWrapImageCreditsWrapsShortCaptionAfterImage() {
        let html = #"<img src="https://example.com/a.jpg"><p>Foto: Test</p><p>Brødtekst.</p>"#
        let result = ArticleHTMLProcessor.wrapImageCredits(in: html)

        XCTAssertTrue(result.contains("apropos-image-credit"))
        XCTAssertTrue(result.contains("Foto: Test"))
    }

    func testWrapImageCreditsIgnoresLongParagraph() {
        let longCaption = String(repeating: "a", count: 90)
        let html = #"<img src="https://example.com/a.jpg"><p>\#(longCaption)</p>"#
        let result = ArticleHTMLProcessor.wrapImageCredits(in: html)

        XCTAssertFalse(result.contains("apropos-image-credit"))
    }

    func testOptimizeInlineImagesAddsLazyPlaceholderForLaterImages() {
        let html = """
        <img src="https://uploads-ssl.webflow.com/a.jpg">
        <img src="https://uploads-ssl.webflow.com/b.jpg">
        """
        let result = ArticleHTMLProcessor.optimizeInlineImages(in: html)

        XCTAssertTrue(result.contains("loading=\"eager\""))
        XCTAssertTrue(result.contains("data-src="))
        XCTAssertTrue(result.contains("apropos-lazy"))
    }

    func testImageURLsExtractsHTTPURLs() {
        let html = """
        <img src="https://example.com/one.jpg">
        <img src="/relative.jpg">
        """
        let urls = ArticleHTMLProcessor.imageURLs(in: html)

        XCTAssertEqual(urls, ["https://example.com/one.jpg"])
    }

    func testOptimizedImageURLAddsWebflowWidthQuery() {
        let src = "https://uploads-ssl.webflow.com/demo/image.jpg"
        let optimized = ArticleHTMLProcessor.optimizedImageURL(from: src)

        XCTAssertTrue(optimized.contains("w="))
        XCTAssertTrue(optimized.contains("q=85"))
    }
}
