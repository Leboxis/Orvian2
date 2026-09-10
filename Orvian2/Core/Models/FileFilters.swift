import Foundation

/// Filtres d'affichage et de tri appliqués localement et côté serveur.
struct FileFilters: Equatable, Hashable {
    enum SortMode: String, CaseIterable, Identifiable {
        case original, modifiedDate, addedDate, type, size, duration
        var id: String { rawValue }

        var label: String {
            switch self {
            case .original: return "Original"
            case .modifiedDate: return "Date de modification"
            case .addedDate: return "Date d'ajout"
            case .type: return "Type"
            case .size: return "Taille"
            case .duration: return "Durée"
            }
        }
    }

    enum Direction: String, CaseIterable, Identifiable {
        case ascending, descending
        var id: String { rawValue }
        var label: String { self == .ascending ? "Croissant" : "Décroissant" }
    }

    enum Orientation: String, CaseIterable, Codable, Identifiable {
        case portrait, landscape, square
        var id: String { rawValue }
        var label: String {
            switch self {
            case .portrait: return "Portrait"
            case .landscape: return "Paysage"
            case .square: return "Carré"
            }
        }
    }

    enum MediaFilter: String, CaseIterable, Identifiable {
        case all, videos, images, other
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "Tout"
            case .videos: return "Vidéos"
            case .images: return "Images"
            case .other: return "Autres"
            }
        }
    }

    var sort: SortMode = .original
    var direction: Direction = .descending
    var orientation: Orientation? = nil
    var highResolutionVideosOnly = false
    var media: MediaFilter = .all

    /// Champs `order_by[]` autorisés côté serveur (nil si tri local uniquement).
    var serverOrderBy: [String]? {
        switch sort {
        case .original, .duration: return nil
        case .modifiedDate: return ["updated_at"]
        case .addedDate: return ["added_at"]
        case .type: return ["type"]
        case .size: return ["size"]
        }
    }

    var serverOrder: String { direction == .ascending ? "asc" : "desc" }

    var isActive: Bool {
        sort != .original || orientation != nil || highResolutionVideosOnly || media != .all
    }

    /// Filtre média → orientation (nécessite métadonnées vidéo) → 4K+ → recherche → tri local.
    func visible(_ items: [DriveFile],
                 searchText: String = "",
                 mediaMetadata: [Int: MediaMetadataStore.Info] = [:]) -> [DriveFile] {
        let keywords = searchText.split(whereSeparator: \.isWhitespace).map(String.init)
        var result = items.filter { file in
            switch media {
            case .all: break
            case .videos: if !file.isVideo { return false }
            case .images: if !file.isImage { return false }
            case .other: if file.isVideo || file.isImage { return false }
            }
            if let orientation {
                guard let info = mediaMetadata[file.id], file.isVideo || file.isImage else { return false }
                if info.orientation != orientation { return false }
            }
            if highResolutionVideosOnly {
                guard file.isVideo, let info = mediaMetadata[file.id], info.is4KOrAbove else { return false }
            }
            if !keywords.isEmpty, !file.matchesSearchKeywords(keywords) { return false }
            return true
        }
        result = sorted(result, metadata: mediaMetadata)
        return result
    }

    private func sorted(_ items: [DriveFile], metadata: [Int: MediaMetadataStore.Info]) -> [DriveFile] {
        guard sort != .original else { return items }
        let asc = direction == .ascending
        return items.sorted { lhs, rhs in
            let comparison = compare(lhs, rhs, metadata: metadata)
            if comparison == .orderedSame {
                let nameComparison = lhs.name.localizedStandardCompare(rhs.name)
                if nameComparison != .orderedSame { return nameComparison == .orderedAscending }
                return lhs.id < rhs.id
            }
            return asc ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    private func compare(_ lhs: DriveFile, _ rhs: DriveFile, metadata: [Int: MediaMetadataStore.Info]) -> ComparisonResult {
        switch sort {
        case .original:
            return .orderedSame
        case .modifiedDate:
            return compareNumbers(lhs.updatedAt ?? lhs.lastModifiedAt, rhs.updatedAt ?? rhs.lastModifiedAt)
        case .addedDate:
            return compareNumbers(lhs.addedAt, rhs.addedAt)
        case .type:
            return lhs.fileKind.rawValue.localizedStandardCompare(rhs.fileKind.rawValue)
        case .size:
            return compareNumbers(lhs.size, rhs.size)
        case .duration:
            return compareNumbers(metadata[lhs.id]?.duration, metadata[rhs.id]?.duration)
        }
    }

    private func compareNumbers<T: Comparable>(_ lhs: T?, _ rhs: T?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (l?, r?): return l < r ? .orderedAscending : (l > r ? .orderedDescending : .orderedSame)
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedAscending
        case (_, nil): return .orderedDescending
        }
    }
}
