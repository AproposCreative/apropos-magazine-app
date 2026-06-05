import Foundation
import UIKit

enum ArticleHTMLProcessor {
    private static let imgTagPattern = #"<img\b([^>]*?)\bsrc\s*=\s*["']([^"']+)["']([^>]*)>"#
    private static let creditPattern = #"(?is)(<img\b[^>]*>)\s*<p(?:\s[^>]*)?>([^<]{1,80})</p>"#

    static func process(_ html: String) -> String {
        var result = optimizeInlineImages(in: html)
        result = wrapImageCredits(in: result)
        return result
    }

    static func optimizeInlineImages(in html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: imgTagPattern, options: [.caseInsensitive]) else {
            return html
        }

        let nsHTML = html as NSString
        var result = html
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)).reversed()

        for match in matches {
            guard match.numberOfRanges >= 4 else { continue }
            let beforeSrc = nsHTML.substring(with: match.range(at: 1))
            let src = nsHTML.substring(with: match.range(at: 2))
            let afterSrc = nsHTML.substring(with: match.range(at: 3))
            let optimizedSrc = optimizedImageURL(from: src)
            let loadingAttr = beforeSrc.contains("loading=") || afterSrc.contains("loading=") ? "" : " loading=\"lazy\""
            let replacement = "<img\(beforeSrc) src=\"\(optimizedSrc)\"\(afterSrc)\(loadingAttr)>"
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }

        return result
    }

    static func imageURLs(in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: imgTagPattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsHTML = html as NSString
        var urls: [String] = []
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        for match in matches where match.numberOfRanges >= 3 {
            let src = nsHTML.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !src.isEmpty, src.hasPrefix("http://") || src.hasPrefix("https://") else { continue }
            urls.append(src)
        }

        return urls
    }

    static func wrapImageCredits(in html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: creditPattern, options: []) else {
            return html
        }

        let nsHTML = html as NSString
        var result = html
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)).reversed()

        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }
            let imgTag = nsHTML.substring(with: match.range(at: 1))
            let creditText = nsHTML.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard isLikelyImageCredit(creditText) else { continue }

            let escapedCredit = creditText
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")

            let replacement = "\(imgTag)<p class=\"apropos-image-credit\"><span>\(escapedCredit)</span></p>"
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }

        return result
    }

    private static func isLikelyImageCredit(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= 80 else { return false }
        if text.contains("\n") { return false }

        let sentenceCount = text.components(separatedBy: CharacterSet(charactersIn: ".!?")).filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        if sentenceCount > 1 { return false }

        return true
    }

    static func optimizedImageURL(from src: String) -> String {
        guard var components = URLComponents(string: src) else { return src }

        let targetWidth = min(1200, Int(UIScreen.main.bounds.width * UIScreen.main.scale))
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "w" || $0.name == "q" || $0.name == "fmt" }
        queryItems.append(URLQueryItem(name: "w", value: "\(targetWidth)"))
        queryItems.append(URLQueryItem(name: "q", value: "85"))
        components.queryItems = queryItems

        return components.string ?? src
    }
}
