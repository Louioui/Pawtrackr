//
//  ImageCache.swift
//  Pawtrackr
//
//  Lightweight in-memory image cache with downsampling.
//  Speeds up repeated decoding of Data-backed images across the app.
//

import Foundation

#if canImport(UIKit)
import UIKit
import ImageIO

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private init() { cache.countLimit = 200 }

    /// Returns a decoded, downsampled UIImage for the given data and max dimension.
    /// Images are cached by a computed key that includes the data hash and target size.
    func image(data: Data, maxDimension: CGFloat) -> UIImage? {
        let key = cacheKey(for: data, maxDimension: maxDimension)
        if let hit = cache.object(forKey: key as NSString) { return hit }

        guard let image = downsample(data: data, maxDimension: maxDimension) else { return nil }
        cache.setObject(image, forKey: key as NSString)
        return image
    }

    private func cacheKey(for data: Data, maxDimension: CGFloat) -> String {
        // Use a quick hash composed of count + a stable NSData hash + dimension
        let h = (data as NSData).hash
        return "\(data.count)-\(h)-\(Int(maxDimension.rounded()))"
    }

    /// Efficient downsampling using CGImageSource; avoids decoding full-resolution into memory.
    private func downsample(data: Data, maxDimension: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let src = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else { return nil }
        let max = max(1, Int(maxDimension * UIScreen.main.scale))
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, downsampleOptions as CFDictionary) else { return nil }
        return UIImage(cgImage: cg, scale: UIScreen.main.scale, orientation: .up)
    }
}
#else
// Fallback stub for non-UIKit platforms
final class ImageCache {
    static let shared = ImageCache()
    private init() {}
}
#endif

