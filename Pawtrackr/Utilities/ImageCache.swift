//
//  ImageCache.swift
//  Pawtrackr
//
//  Thread-safe, lightweight in-memory image cache with downsampling.
//  Speeds up repeated decoding of Data-backed images across the app.
//

import Foundation

#if canImport(UIKit)
import UIKit
import ImageIO

final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private let lock = NSLock()

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB limit

        // Clear cache on memory warning
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clearCache()
        }
    }

    /// Returns a decoded, downsampled UIImage for the given data and max dimension.
    /// Thread-safe: can be called from any thread.
    func image(data: Data, maxDimension: CGFloat) -> UIImage? {
        let key = cacheKey(for: data, maxDimension: maxDimension) as NSString

        // Check cache first (fast lock-based read)
        lock.lock()
        let cachedImage = cache.object(forKey: key)
        lock.unlock()
        if let hit = cachedImage { return hit }

        // Decode image (can happen on any thread, outside lock)
        guard let image = downsample(data: data, maxDimension: maxDimension) else { return nil }

        // Store in cache
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        lock.lock()
        cache.setObject(image, forKey: key, cost: cost)
        lock.unlock()

        return image
    }

    /// Clears all cached images. Thread-safe.
    func clearCache() {
        lock.lock()
        cache.removeAllObjects()
        lock.unlock()
    }

    /// Removes a specific image from cache. Thread-safe.
    func removeImage(for data: Data, maxDimension: CGFloat) {
        let key = cacheKey(for: data, maxDimension: maxDimension) as NSString
        lock.lock()
        cache.removeObject(forKey: key)
        lock.unlock()
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

        let scale = UIScreen.main.scale
        let maxPixels = max(1, Int(maxDimension * scale))

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, downsampleOptions as CFDictionary) else { return nil }
        return UIImage(cgImage: cg, scale: scale, orientation: .up)
    }
}
#elseif canImport(AppKit)
import AppKit
import ImageIO

final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, NSImage>()
    private let lock = NSLock()

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB limit
    }

    /// Returns a decoded, downsampled NSImage for the given data and max dimension.
    /// Thread-safe: can be called from any thread.
    func image(data: Data, maxDimension: CGFloat) -> NSImage? {
        let key = cacheKey(for: data, maxDimension: maxDimension) as NSString

        // Check cache first (fast lock-based read)
        lock.lock()
        let cachedImage = cache.object(forKey: key)
        lock.unlock()
        if let hit = cachedImage { return hit }

        // Decode image (can happen on any thread, outside lock)
        guard let image = downsample(data: data, maxDimension: maxDimension) else { return nil }

        // Store in cache
        let cost = Int(image.size.width * image.size.height * 4)
        lock.lock()
        cache.setObject(image, forKey: key, cost: cost)
        lock.unlock()

        return image
    }

    /// Clears all cached images. Thread-safe.
    func clearCache() {
        lock.lock()
        cache.removeAllObjects()
        lock.unlock()
    }

    /// Removes a specific image from cache. Thread-safe.
    func removeImage(for data: Data, maxDimension: CGFloat) {
        let key = cacheKey(for: data, maxDimension: maxDimension) as NSString
        lock.lock()
        cache.removeObject(forKey: key)
        lock.unlock()
    }

    private func cacheKey(for data: Data, maxDimension: CGFloat) -> String {
        let h = (data as NSData).hash
        return "\(data.count)-\(h)-\(Int(maxDimension.rounded()))"
    }

    /// Efficient downsampling using CGImageSource; avoids decoding full-resolution into memory.
    private func downsample(data: Data, maxDimension: CGFloat) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let src = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else { return nil }

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let maxPixels = max(1, Int(maxDimension * scale))

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, downsampleOptions as CFDictionary) else { return nil }

        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
#endif

