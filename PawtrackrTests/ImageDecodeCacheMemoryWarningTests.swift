//
//  ImageDecodeCacheMemoryWarningTests.swift
//  PawtrackrTests
//
//  The decoded-image cache behind photo avatars kept up to 200 decoded
//  images through memory warnings, pinning what ImageCache's NSCache had
//  just released. A warning must empty it.
//

#if canImport(UIKit)
import XCTest
import SwiftUI
import UIKit
@testable import Pawtrackr

@MainActor
final class ImageDecodeCacheMemoryWarningTests: XCTestCase {
    func testMemoryWarningEmptiesTheDecodedImageCache() {
        let cache = ImageDataDecodeCache.shared
        for index in 0..<5 {
            cache.store(Image(systemName: "star"), for: ImageDataIdentity(data: Data([UInt8(index), 1, 2, 3]), maxDimension: 64))
        }
        XCTAssertGreaterThanOrEqual(cache.count, 5)

        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)

        // The observer runs on the main queue; let it.
        let deadline = Date().addingTimeInterval(2)
        while cache.count > 0, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(cache.count, 0)
    }
}
#endif
