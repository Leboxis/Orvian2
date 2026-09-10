import UIKit

/// Fournit les miniatures avec cache mémoire, cache disque, déduplication et retries.
actor ThumbnailProvider {
    static let shared = ThumbnailProvider()

    private static let memoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 600
        cache.totalCostLimit = 80 * 1024 * 1024
        return cache
    }()

    private let throttler = AsyncThrottler(maxConcurrent: 9)
    private let service = KDriveService()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private var recentFailures: [String: Date] = [:]
    private let failureTTL: TimeInterval = 300
    private let failureLimit = 512

    private var prefetchQueue: [(driveId: Int, fileId: Int, isTrashed: Bool)] = []
    private let prefetchCapacity = 6

    /// Lecture synchrone du cache mémoire (utilisable depuis le MainActor).
    nonisolated static func cachedMemoryThumbnail(driveId: Int, fileId: Int) -> UIImage? {
        memoryCache.object(forKey: cacheKey(driveId: driveId, fileId: fileId))
    }

    private nonisolated static func cacheKey(driveId: Int, fileId: Int) -> NSString {
        "\(driveId)-\(fileId)" as NSString
    }

    func thumbnail(driveId: Int, fileId: Int, isTrashed: Bool = false) async -> UIImage? {
        let key = "\(driveId)-\(fileId)"
        if let cached = Self.memoryCache.object(forKey: key as NSString) { return cached }
        if let failure = recentFailures[key], Date().timeIntervalSince(failure) < failureTTL { return nil }
        if let task = inFlight[key] { return await task.value }

        let task = Task<UIImage?, Never> { [throttler, service] in
            await throttler.withPermit {
                if let diskImage = await Task.detached(priority: .userInitiated, operation: {
                    DiskImageCache.shared.loadImage(driveId: driveId, fileId: fileId)
                }).value {
                    Self.store(diskImage, key: key)
                    return diskImage
                }
                do {
                    let data = try await service.thumbnailData(driveId: driveId, fileId: fileId, isTrashed: isTrashed)
                    let image = await Self.decode(data)
                    if let image {
                        Self.store(image, key: key)
                        await Task.detached(priority: .utility) {
                            DiskImageCache.shared.store(driveId: driveId, fileId: fileId, data: data)
                        }.value
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
        if image == nil { recordFailure(key) }
        return image
    }

    /// Attend la disponibilité de la miniature après upload (retries progressifs).
    func thumbnailWhenAvailable(driveId: Int, fileId: Int) async -> UIImage? {
        let delays: [UInt64] = [0, 2, 3, 5, 8, 12, 15, 15]
        for delay in delays {
            if delay > 0 { try? await Task.sleep(nanoseconds: delay * 1_000_000_000) }
            if let image = await thumbnail(driveId: driveId, fileId: fileId) { return image }
        }
        return nil
    }

    func primeUploadedThumbnail(driveId: Int, fileId: Int) {
        Task { _ = await thumbnailWhenAvailable(driveId: driveId, fileId: fileId) }
    }

    func prefetch(driveId: Int, fileId: Int, isTrashed: Bool = false) {
        let key = "\(driveId)-\(fileId)"
        if Self.memoryCache.object(forKey: key as NSString) != nil { return }
        guard !prefetchQueue.contains(where: { $0.driveId == driveId && $0.fileId == fileId }) else { return }
        prefetchQueue.append((driveId, fileId, isTrashed))
        if prefetchQueue.count > prefetchCapacity { prefetchQueue.removeFirst() }
        Task { await drainPrefetch() }
    }

    func cancelPrefetch(driveId: Int, fileId: Int) {
        prefetchQueue.removeAll { $0.driveId == driveId && $0.fileId == fileId }
    }

    func purgeDiskCache() {
        DiskImageCache.shared.purge()
        Self.memoryCache.removeAllObjects()
    }

    func diskCacheSize() -> Int64 {
        DiskImageCache.shared.totalSize()
    }

    func enforceDiskLimit() {
        DiskImageCache.shared.enforceSizeLimit()
    }

    private func drainPrefetch() async {
        guard let next = prefetchQueue.first else { return }
        prefetchQueue.removeFirst()
        _ = await thumbnail(driveId: next.driveId, fileId: next.fileId, isTrashed: next.isTrashed)
    }

    private nonisolated static func decode(_ data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            UIImage(data: data)?.preparingForDisplay() ?? UIImage(data: data)
        }.value
    }

    private nonisolated static func store(_ image: UIImage, key: String) {
        let cost = Int(image.size.width * image.size.height * 4)
        memoryCache.setObject(image, forKey: key as NSString, cost: cost)
    }

    private func recordFailure(_ key: String) {
        if recentFailures.count >= failureLimit {
            recentFailures.removeAll()
        }
        recentFailures[key] = Date()
    }
}
