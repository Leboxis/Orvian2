import UIKit

/// Cache des URLs temporaires signées (TTL 3300 s) avec déduplication.
actor MediaURLCache {
    static let shared = MediaURLCache()

    private struct Entry {
        let url: URL
        let expiry: Date
    }

    private let service = KDriveService()
    private let ttl: TimeInterval = 3300
    private let margin: TimeInterval = 30
    private var entries: [Key: Entry] = [:]
    private var inFlight: [Key: Task<URL, Error>] = [:]
    private let prefetchThrottler = AsyncThrottler(maxConcurrent: 2)

    struct Key: Hashable {
        let driveId: Int
        let fileId: Int
        let fingerprint: String
    }

    private func makeKey(driveId: Int, fileId: Int) -> Key {
        Key(driveId: driveId, fileId: fileId, fingerprint: TokenStore.credentialFingerprint() ?? "anon")
    }

    func url(driveId: Int, fileId: Int) async throws -> URL {
        let key = makeKey(driveId: driveId, fileId: fileId)
        if let entry = entries[key], entry.expiry.timeIntervalSinceNow > margin { return entry.url }
        if let task = inFlight[key] { return try await task.value }
        let task = Task<URL, Error> { [service] in
            let url = try await service.temporaryURL(driveId: driveId, fileId: fileId)
            return url
        }
        inFlight[key] = task
        do {
            let url = try await task.value
            entries[key] = Entry(url: url, expiry: Date().addingTimeInterval(ttl))
            inFlight[key] = nil
            return url
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    func freshURL(driveId: Int, fileId: Int) async throws -> URL {
        invalidate(driveId: driveId, fileId: fileId)
        return try await url(driveId: driveId, fileId: fileId)
    }

    func invalidate(driveId: Int, fileId: Int) {
        entries[makeKey(driveId: driveId, fileId: fileId)] = nil
    }

    func prefetch(driveId: Int, fileId: Int) {
        Task {
            _ = try? await prefetchThrottler.withPermit {
                try await url(driveId: driveId, fileId: fileId)
            }
        }
    }

    func cancelPrefetch(driveId: Int, fileId: Int) {
        invalidate(driveId: driveId, fileId: fileId)
    }
}
