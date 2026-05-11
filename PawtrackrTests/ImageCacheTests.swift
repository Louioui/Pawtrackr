import XCTest
@testable import Pawtrackr

final class ImageCacheTests: XCTestCase {
    
    func testDownsampleToData_ReducesSize() {
        // Create a fake large-ish red square image
        #if canImport(UIKit)
        let size = CGSize(width: 500, height: 500)
        UIGraphicsBeginImageContext(size)
        UIColor.red.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        let data = image?.jpegData(compressionQuality: 1.0)
        #else
        let size = NSSize(width: 500, height: 500)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.set()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        let data = image.tiffRepresentation
        #endif
        
        guard let originalData = data else {
            XCTFail("Failed to create test image data")
            return
        }
        
        // Downsample to 100px
        let downsampledData = ImageCache.shared.downsampleToData(data: originalData, maxDimension: 100)
        
        XCTAssertNotNil(downsampledData)
        XCTAssertTrue(downsampledData!.count < originalData.count)
    }
    
    func testCache_StoresAndRetrievesImage() {
        #if canImport(UIKit)
        let size = CGSize(width: 50, height: 50)
        UIGraphicsBeginImageContext(size)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        let data = image?.pngData()
        #else
        let size = NSSize(width: 50, height: 50)
        let image = NSImage(size: size)
        let data = image.tiffRepresentation
        #endif
        
        guard let testData = data else { return }
        
        let cached1 = ImageCache.shared.image(data: testData, maxDimension: 50)
        XCTAssertNotNil(cached1)
        
        let cached2 = ImageCache.shared.image(data: testData, maxDimension: 50)
        XCTAssertNotNil(cached2)
        
        // Verify it hits the same object (using the same data should hit cache)
        XCTAssertEqual(cached1, cached2)
    }
}
