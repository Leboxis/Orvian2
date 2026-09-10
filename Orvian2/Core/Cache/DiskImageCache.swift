import UIKit

/// Cache disque des miniatures, avec éviction Oldest-Written et limite configurable.
final class DiskImageCache: @unchecked Sendable {
    static let shared = DiskImageCache()

    private let root: URL
    private let lock = NSLock()
    private var writesSinceScan = 0
    private var purgeGeneration = 0

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        root = base.appendingPathComponent("thumbnails", isDirectory: true)
    }

    private var limitBytes: Int64 {
        let mb = UserDefaults.standard.object(forKey: "thumbnailCacheLimitMB") as? Int ?? 250
        return mb <= 0 ? .max : Int64(mb) * 1024 * 1024
    }

    private func url(driveId: Int, fileId: Int) -> URL {
        root.appendingPathComponent("\(driveId)", isDirectory: true)
            .appendingPathComponent("\(fileId).jpg")
    }

    func hasEntry(driveId: Int, fileId: Int) -> Bool {
        FileManager.default.fileExists(atPath: url(driveId: driveId, fileId: fileId).path)
    }

    func loadImage(driveId: Int, fileId: Int) -> UIImage? {
        guard let data = try? Data(contentsOf: url(driveId: driveId, fileId: fileId)) else { return nil }
        return UIImage(data: data)
    }

    func removeEntry(driveId: Int, fileId: Int) {
        try? FileManager.default.removeItem(at: url(driveId: driveId, fileId: fileId))
    }

    func store(driveId: Int, fileId: Int, data: Data) {
        let destination = url(driveId: driveId, fileId: fileId)
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: destination, options: .atomic)
        lock.lock()
        writesSinceScan += 1
        let shouldScan = writesSinceScan >= 150
        if shouldScan { writesSinceScan = 0 }
        lock.unlock()
        if shouldScan { enforceSizeLimit() }
    }

    func purge() {
        lock.lock()
        purgeGeneration += 1
        lock.unlock()
        try? FileManager.default.removeItem(at: root)
    }

    func totalSize() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: root,
                                                              includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    func enforceSizeLimit() {
        let limit = limitBytes
        guard limit != .max else { return }
        let lowWatermark = Int64(Double(limit) * 0.8)
        let current = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) != nil
            ? totalSize() : 0
        guard current > limit else { return }
        evictOldest(until: lowWatermark)
    }

    private func evictOldest(until target: Int64) {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return }
        var entries: [(url: URL, date: Date, size: Int64)] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            entries.append((url, values?.contentModificationDate ?? .distantPast, Int64(values?.fileSize ?? 0)))
        }
        entries.sort { $0.date < $1.date }
        var total = entries.reduce(Int64(0)) { $0 + $1.size }
        var index = 0
        while total > target, index < entries.count {
            try? FileManager.default.removeItem(at: entries[index].url)
            total -= entries[index].size
            index += 1
        }
    }
}
