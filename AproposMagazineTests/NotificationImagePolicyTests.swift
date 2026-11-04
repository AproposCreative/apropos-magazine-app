import CoreGraphics
import ImageIO
import XCTest
@testable import Apropos

final class NotificationImagePolicyTests: XCTestCase {
    func testOnlyHTTPSWithoutEmbeddedCredentialsIsAllowed() throws {
        XCTAssertTrue(NotificationImagePolicy.isAllowedURL(try XCTUnwrap(URL(string: "https://images.example.org/cover.png"))))
        for value in ["http://images.example.org/a.png", "file:///tmp/a.png", "https://user:password@images.example.org/a.png"] {
            XCTAssertFalse(NotificationImagePolicy.isAllowedURL(try XCTUnwrap(URL(string: value))))
        }
    }

    func testResponseRequiresSuccessSupportedImageMIMEAndBoundedLength() {
        XCTAssertTrue(NotificationImagePolicy.allowsResponse(statusCode: 200, mimeType: "image/png", expectedLength: 200))
        XCTAssertTrue(NotificationImagePolicy.allowsResponse(statusCode: 200, mimeType: "image/jpeg", expectedLength: NSURLSessionTransferSizeUnknown))
        XCTAssertFalse(NotificationImagePolicy.allowsResponse(statusCode: 404, mimeType: "image/png", expectedLength: 200))
        XCTAssertFalse(NotificationImagePolicy.allowsResponse(statusCode: 200, mimeType: "text/html", expectedLength: 200))
        XCTAssertFalse(NotificationImagePolicy.allowsResponse(statusCode: 200, mimeType: "image/png", expectedLength: Int64(NotificationImagePolicy.maximumBytes + 1)))
    }

    func testValidImagesUseTheirActualAttachmentFormat() throws {
        for format in [NotificationImagePolicy.Format.png, .jpeg, .gif] {
            let imageData = try makeImageData(format: format)
            XCTAssertEqual(NotificationImagePolicy.validatedFormat(for: imageData, mimeType: format.mimeType), format)
        }
    }

    func testMislabelledTruncatedAndOversizedImagesAreRejected() throws {
        let png = try makeImageData(format: .png)
        XCTAssertNil(NotificationImagePolicy.validatedFormat(for: png, mimeType: "image/jpeg"))
        XCTAssertNil(NotificationImagePolicy.validatedFormat(for: Data(png.prefix(8)), mimeType: "image/png"))
        XCTAssertNil(NotificationImagePolicy.validatedFormat(for: Data("<html>error</html>".utf8), mimeType: "image/png"))
        XCTAssertNil(NotificationImagePolicy.validatedFormat(for: Data(count: NotificationImagePolicy.maximumBytes + 1), mimeType: "image/png"))
    }

    private func makeImageData(format: NotificationImagePolicy.Format) throws -> Data {
        let pixels = Data([0, 0, 0, 255])
        let provider = try XCTUnwrap(CGDataProvider(data: pixels as CFData))
        let image = try XCTUnwrap(CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, format.typeIdentifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
