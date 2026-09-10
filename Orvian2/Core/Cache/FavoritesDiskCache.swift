import Foundation

/// Cache disque persistant des listings favoris/récents (JSON).
actor FavoritesDiskCache {
    static let shared = FavoritesDiskCache()

    private let maximumAge: TimeInterval = 7 * 24 * 3600
    private let maxFileSize = 2 * 1024 * 1024
    private let maxTotalSize = 10 * 1024 * 1024
    private let maxFiles = 20

    private var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Orvian2Favorites", isDirectory: true)
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent("\(SHA256.hash(key)).json")
    }

    func load(key: String) -> DirectoryListSnapshot? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        guard Date().timeIntervalSince1970 - payload.timestamp < maximumAge else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return payload.snapshot
    }

    func save(_ snapshot: DirectoryListSnapshot, key: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload = Payload(version: 1, key: key, timestamp: Date().timeIntervalSince1970, snapshot: snapshot)
        guard let data = try? JSONEncoder().encode(payload), data.count <= maxFileSize else { return }
        let url = fileURL(for: key)
        try? data.write(to: url, options: .atomic)
        pruneIfNeeded()
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func pruneIfNeeded() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                       includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return }
        var entries: [(url: URL, date: Date, size: Int)] = files.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return (url, values?.contentModificationDate ?? .distantPast, values?.fileSize ?? 0)
        }
        var totalSize = entries.reduce(0) { $0 + $1.size }
        entries.sort { $0.date < $1.date }
        while (entries.count > maxFiles || totalSize > maxTotalSize), let oldest = entries.first {
            try? FileManager.default.removeItem(at: oldest.url)
            totalSize -= oldest.size
            entries.removeFirst()
        }
    }

    private struct Payload: Codable {
        let version: Int
        let key: String
        let timestamp: TimeInterval
        let snapshot: DirectoryListSnapshot
    }
}
