import Foundation
import Observation

/// Bibliothèque de catégories par drive, avec cache mémoire.
@MainActor
@Observable
final class CategoryLibrary {
    static let shared = CategoryLibrary()

    private(set) var categoriesByDrive: [Int: [Category]] = [:]
    private var loadedDrives: Set<Int> = []
    private var loadingDrives: Set<Int> = []

    private let service = KDriveService()

    func categories(for driveId: Int) -> [Category] { categoriesByDrive[driveId] ?? [] }

    func category(id: Int, driveId: Int) -> Category? {
        categoriesByDrive[driveId]?.first { $0.id == id }
    }

    func ensureLoaded(driveId: Int) async {
        guard !loadedDrives.contains(driveId), !loadingDrives.contains(driveId) else { return }
        loadingDrives.insert(driveId)
        defer { loadingDrives.remove(driveId) }
        if let categories = try? await service.categories(driveId: driveId) {
            categoriesByDrive[driveId] = categories
            loadedDrives.insert(driveId)
        }
    }

    func refresh(driveId: Int) async {
        loadedDrives.remove(driveId)
        await ensureLoaded(driveId: driveId)
    }

    func upsert(_ category: Category, driveId: Int) {
        var categories = categoriesByDrive[driveId] ?? []
        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            categories[index] = category
        } else {
            categories.append(category)
        }
        categoriesByDrive[driveId] = categories
    }

    func remove(categoryId: Int, driveId: Int) {
        categoriesByDrive[driveId]?.removeAll { $0.id == categoryId }
    }

    func clear() {
        categoriesByDrive.removeAll()
        loadedDrives.removeAll()
        loadingDrives.removeAll()
    }
}

/// Mémorise l'ordre d'affichage des tags par drive.
enum TagOrderStore {
    private static func key(driveId: Int) -> String { "tag-order-\(driveId)" }

    static func order(for driveId: Int) -> [Int]? {
        guard let stored = UserDefaults.standard.array(forKey: key(driveId: driveId)) as? [Int],
              !stored.isEmpty else { return nil }
        return stored
    }

    static func save(_ order: [Int], driveId: Int) {
        UserDefaults.standard.set(order, forKey: key(driveId: driveId))
    }
}
