import Foundation

/// Formatage de tailles de fichiers.
enum ByteFormatter {
    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter
    }()

    static func string(_ bytes: Int?) -> String {
        guard let bytes, bytes >= 0 else { return "—" }
        return formatter.string(fromByteCount: Int64(bytes))
    }

    static func format(_ bytes: Int64?) -> String {
        guard let bytes, bytes >= 0 else { return "—" }
        return formatter.string(fromByteCount: bytes)
    }

    static func usage(used: Int?, total: Int?) -> String {
        guard let used, let total, total > 0 else {
            return string(used)
        }
        return "\(string(used)) sur \(string(total))"
    }
}
