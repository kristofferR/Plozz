import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import TopShelfKit

@MainActor
final class HomeTopShelfExportHostedTests: XCTestCase {
    func testHomeTopShelfExportPreservesTransparentArtworkPixels() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 180)).image {
            UIColor.red.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 60, height: 180))
            UIColor.blue.setFill()
            $0.fill(CGRect(x: 20, y: 30, width: 60, height: 90))
        }
        let expected = try XCTUnwrap(image.pngData())
        let encoded = await TopShelfPosterComposer.encodedArtwork(image)
        XCTAssertEqual(encoded, expected)
    }

    func testOpaqueArtworkUsesJPEGWithoutChangingDimensions() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 180), format: format).image {
            UIColor.blue.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 120, height: 180))
        }
        let encoded = await TopShelfPosterComposer.encodedArtwork(image)
        let data = try XCTUnwrap(encoded)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source), UTType.jpeg.identifier as CFString)
        XCTAssertEqual(try XCTUnwrap(UIImage(data: data)).size, image.size)
    }

    func testCancelledHomeTopShelfExportSkipsEncoding() async {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 180)).image { _ in }
        let export = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await TopShelfPosterComposer.encodedArtwork(image)
        }
        let encoded = await export.value
        XCTAssertNil(encoded)
    }

    func testExportReusesMatchingCachedJPEGButRejectsFullSizeBytes() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 180), format: format).image {
            UIColor.red.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 120, height: 180))
        }
        let jpeg = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
        let reused = await TopShelfPosterComposer.encodedArtwork(image, cachedData: jpeg)
        XCTAssertEqual(reused, jpeg)

        let larger = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 360), format: format).image { _ in }
        let encoded = await TopShelfPosterComposer.encodedArtwork(image, cachedData: larger.jpegData(compressionQuality: 0.8))
        let decoded = try XCTUnwrap(UIImage(data: XCTUnwrap(encoded)))
        XCTAssertEqual(decoded.size, image.size)
    }

    func testSelectedPosterCopiesJPEGAndCompositesOnlyResumeArtwork() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 180)).image {
            UIColor.red.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 120, height: 180))
        }
        let jpeg = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
        let plain = try XCTUnwrap(TopShelfPosterComposer.selectedPosterURL(
            id: "poster", data: jpeg, progress: nil, chip: nil, directory: directory
        ))
        XCTAssertEqual(plain.pathExtension, "jpg")
        XCTAssertEqual(try Data(contentsOf: plain), jpeg)
        let resumed = try XCTUnwrap(TopShelfPosterComposer.selectedPosterURL(
            id: "poster", data: jpeg, progress: 0.5, chip: "21m", directory: directory
        ))
        XCTAssertEqual(resumed.pathExtension, "jpg")
        XCTAssertNotEqual(resumed, plain)
        XCTAssertNotEqual(try Data(contentsOf: resumed), jpeg)
        XCTAssertNotNil(UIImage(contentsOfFile: resumed.path))
        XCTAssertNil(TopShelfPosterComposer.selectedPosterURL(
            id: "bad", data: Data([1, 2, 3]), progress: nil, chip: nil, directory: directory
        ))
    }

}
