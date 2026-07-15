import AppKit
import Foundation
import ImageIO

enum ImageThumbnailCache {
    private static let cache = NSCache<NSString, NSImage>()
    private static let queue = DispatchQueue(label: "com.macpaste.image-cache", qos: .userInitiated)

    static func thumbnail(for path: String, maxPixelSize: CGFloat, completion: @escaping (NSImage?) -> Void) {
        load(path: path, maxPixelSize: maxPixelSize, completion: completion)
    }

    static func fullImage(for path: String, completion: @escaping (NSImage?) -> Void) {
        load(path: path, maxPixelSize: nil, completion: completion)
    }

    private static func load(path: String, maxPixelSize: CGFloat?, completion: @escaping (NSImage?) -> Void) {
        let cacheKey = "\(path)_\(maxPixelSize.map { String(format: "%.0f", $0) } ?? "full")" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            completion(cached)
            return
        }

        queue.async {
            let image = decodeImage(at: path, maxPixelSize: maxPixelSize)
            if let image {
                cache.setObject(image, forKey: cacheKey)
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    private static func decodeImage(at path: String, maxPixelSize: CGFloat?) -> NSImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else {
            return nil
        }

        if let maxPixelSize {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }

        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

enum PasteboardGuard {
    private static var suppressedChangeCount: Int?

    static func suppress(changeCount: Int) {
        suppressedChangeCount = changeCount
    }

    static func shouldSuppress(changeCount: Int) -> Bool {
        guard let suppressedChangeCount else { return false }
        self.suppressedChangeCount = nil
        return changeCount == suppressedChangeCount
    }
}
