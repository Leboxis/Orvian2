import AVFoundation
import UIKit

/// Cache LRU d'`AVURLAsset` pour la lecture vidéo.
@MainActor
final class VideoAssetCache {
    static let shared = VideoAssetCache()

    private struct Entry {
        let asset: AVURLAsset
        let key: String
    }

    private var entries: [Entry] = []
    private let capacity = 8

    func asset(driveId: Int, fileId: Int) async -> AVURLAsset? {
        let key = "\(driveId)-\(fileId)-\(TokenStore.credentialFingerprint() ?? "anon")"
        if let existing = entries.first(where: { $0.key == key }) {
            promote(key)
            return existing.asset
        }
        do {
            let url = try await MediaURLCache.shared.url(driveId: driveId, fileId: fileId)
            guard url.scheme == "https" else { return nil }
            let asset = AVURLAsset(url: url)
            entries.insert(Entry(asset: asset, key: key), at: 0)
            if entries.count > capacity { entries.removeLast() }
            return asset
        } catch {
            return nil
        }
    }

    func prefetch(driveId: Int, fileId: Int) {
        Task {
            guard let asset = await asset(driveId: driveId, fileId: fileId) else { return }
            _ = try? await asset.load(.isPlayable)
        }
    }

    func cancelPrefetch(driveId: Int, fileId: Int) {
        let key = "\(driveId)-\(fileId)-\(TokenStore.credentialFingerprint() ?? "anon")"
        entries.removeAll { $0.key == key }
    }

    func invalidate(driveId: Int, fileId: Int) {
        cancelPrefetch(driveId: driveId, fileId: fileId)
        MediaURLCache.shared.invalidate(driveId: driveId, fileId: fileId)
    }

    private func promote(_ key: String) {
        guard let index = entries.firstIndex(where: { $0.key == key }), index != 0 else { return }
        let entry = entries.remove(at: index)
        entries.insert(entry, at: 0)
    }
}
