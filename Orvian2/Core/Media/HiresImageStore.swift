import ImageIO
import UIKit

/// Charge et décode les images pleine résolution (ImageIO downsampling).
actor HiresImageStore {
    static let shared = HiresImageStore()

    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 3
        cache.totalCostLimit = 192 * 1024 * 1024
        return cache
    }()

    private let throttler = AsyncThrottler(maxConcurrent: 2)
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    func image(driveId: Int, fileId: Int) async -> UIImage? {
        let key = "\(driveId)-\(fileId)"
        if let cached = Self.cache.object(forKey: key as NSString) { return cached }
        if let task = inFlight[key] { return await task.value }

        let task = Task<UIImage?, Never> { [throttler] in
            await throttler.withPermit {
                do {
                    let url = try await MediaURLCache.shared.url(driveId: driveId, fileId: fileId)
                    let (localURL, _) = try await URLSession.shared.download(from: url)
                    let image = await Self.decodeOriginal(fromFile: localURL)
                    if let image {
                        let cost = Int(image.size.width * image.size.height * 4)
                        Self.cache.setObject(image, forKey: key as NSString, cost: cost)
                    }
                    return image
                } catch {
                    return nil
                }
            }
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        return image
    }

    /// Décodage downsample ImageIO depuis un fichier local.
    nonisolated static func decodeOriginal(fromFile url: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return UIImage(cgImage: cgImage)
        }.value
    }
}
