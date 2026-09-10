import Foundation
import Observation

/// Instantané d'un listing de dossier, mis en cache pour un affichage instantané.
struct DirectoryListSnapshot: Codable {
    var items: [DriveFile]
    var cursor: String?
    var hasMore: Bool
    var totalItemCount: Int?
    var orderBy: [String]?
    var order: String
    var fetchedAt: Date
}

/// Cache mémoire des listings, avec persistance disque pour favoris/récents.
@MainActor
@Observable
final class DirectoryListStore {
    static let shared = DirectoryListStore()

    private struct Entry {
        var snapshot: DirectoryListSnapshot
        var timestamp: Date
    }

    private let ttl: TimeInterval = 300
    private let capacity = 50
    private var storage: [String: Entry] = [:]

    private func key(driveId: Int, source: FileSource, orderBy: [String]?, order: String) -> String {
        // Une recherche n'est jamais mise en cache.
        if case .search(_, _) = source { return "" }
        let fingerprint = TokenStore.credentialFingerprint() ?? "anon"
        let ordering = "\((orderBy ?? []).joined(separator: ","))|\(order)"
        return "\(fingerprint)|\(driveId)|\(source.stableKey)|\(ordering)"
    }

    func snapshot(driveId: Int, source: FileSource, orderBy: [String]?, order: String) -> DirectoryListSnapshot? {
        let key = key(driveId: driveId, source: source, orderBy: orderBy, order: order)
        guard !key.isEmpty, let entry = storage[key] else { return nil }
        if Date().timeIntervalSince(entry.timestamp) > ttl { return nil }
        return entry.snapshot
    }

    func store(_ snapshot: DirectoryListSnapshot, driveId: Int, source: FileSource, orderBy: [String]?, order: String) {
        let key = key(driveId: driveId, source: source, orderBy: orderBy, order: order)
        guard !key.isEmpty else { return }
        evictIfNeeded()
        storage[key] = Entry(snapshot: snapshot, timestamp: Date())
    }

    func diskSnapshot(driveId: Int, source: FileSource, orderBy: [String]?, order: String) async -> DirectoryListSnapshot? {
        guard source.isPersistedList else { return nil }
        let key = key(driveId: driveId, source: source, orderBy: orderBy, order: order)
        guard !key.isEmpty else { return nil }
        return await FavoritesDiskCache.shared.load(key: key)
    }

    func persist(_ snapshot: DirectoryListSnapshot, driveId: Int, source: FileSource, orderBy: [String]?, order: String) {
        guard source.isPersistedList else { return }
        let key = key(driveId: driveId, source: source, orderBy: orderBy, order: order)
        guard !key.isEmpty else { return }
        Task.detached(priority: .utility) {
            await FavoritesDiskCache.shared.save(snapshot, key: key)
        }
    }

    /// Fusionne des uploads locaux récents dans les listings concernés.
    func mergeRecentUploads(_ files: [DriveFile], driveId: Int) {
        for key in storage.keys where key.contains("|\(driveId)|recents-") {
            guard var entry = storage[key] else { continue }
            let existingIDs = Set(entry.snapshot.items.map(\.id))
            let newItems = files.filter { !existingIDs.contains($0.id) }
            guard !newItems.isEmpty else { continue }
            entry.snapshot.items.insert(contentsOf: newItems, at: 0)
            storage[key] = entry
        }
    }

    func clear() {
        storage.removeAll()
    }

    private func evictIfNeeded() {
        guard storage.count > capacity else { return }
        let sorted = storage.sorted { $0.value.timestamp < $1.value.timestamp }
        for (key, _) in sorted.prefix(storage.count - capacity) {
            storage.removeValue(forKey: key)
        }
    }
}
