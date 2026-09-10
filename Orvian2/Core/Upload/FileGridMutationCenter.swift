import Combine
import Foundation

/// Diffuse les mutations confirmées (favori, catégorie, suppression, upload)
/// sans recharger les listings.
enum FileGridMutation {
    case favorite(driveId: Int, fileId: Int, isFavorite: Bool)
    case category(driveId: Int, fileId: Int, categoryId: Int, isApplied: Bool)
    case removal(driveId: Int, fileIds: [Int])
    case uploaded(driveId: Int)

    var driveId: Int {
        switch self {
        case let .favorite(driveId, _, _): return driveId
        case let .category(driveId, _, _, _): return driveId
        case let .removal(driveId, _): return driveId
        case let .uploaded(driveId): return driveId
        }
    }
}

final class FileGridMutationCenter {
    static let shared = FileGridMutationCenter()
    let mutations = PassthroughSubject<FileGridMutation, Never>()
    private init() {}

    func publish(_ mutation: FileGridMutation) {
        mutations.send(mutation)
    }
}
