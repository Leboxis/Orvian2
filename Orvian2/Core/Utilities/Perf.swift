import SwiftUI

/// Suivi des performances réseau (optionnel, activé par défaut).
@MainActor
final class Perf: ObservableObject {
    static let shared = Perf()

    struct Entry: Identifiable {
        let id = UUID()
        let method: String
        let path: String
        let status: Int
        let durationMs: Double
        let bytes: Int
        let fromCache: Bool
    }

    @Published private(set) var entries: [Entry] = []
    private let maximumEntries = 400

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "networkPerfEnabled") as? Bool ?? true
    }

    func record(method: String, path: String, status: Int,
                durationMs: Double, bytes: Int, fromCache: Bool) {
        guard isEnabled else { return }
        guard !path.hasSuffix("/thumbnail") else { return }
        entries.append(Entry(method: method, path: path, status: status,
                             durationMs: durationMs, bytes: bytes, fromCache: fromCache))
        if entries.count > maximumEntries { entries.removeFirst(entries.count - maximumEntries) }
    }

    func endpointName(for entry: Entry) -> String {
        let segments = entry.path.split(separator: "/")
        guard let last = segments.last else { return entry.path }
        return Int(last) != nil ? "resource/{id}" : String(last)
    }

    struct EndpointStat: Identifiable {
        let name: String
        let count: Int
        let averageMs: Double
        var id: String { name }
    }

    var statsByEndpoint: [EndpointStat] {
        var buckets: [String: [Double]] = [:]
        for entry in entries {
            buckets[endpointName(for: entry), default: []].append(entry.durationMs)
        }
        return buckets.map { key, values in
            EndpointStat(name: key, count: values.count,
                         averageMs: values.reduce(0, +) / Double(max(1, values.count)))
        }.sorted { $0.averageMs > $1.averageMs }
    }

    func clear() { entries.removeAll() }
}

#if DEBUG
extension Perf {
    static func signpost(_ name: String) {}
}
#endif
