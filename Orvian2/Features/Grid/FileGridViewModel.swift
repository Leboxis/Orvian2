import Foundation
import Observation

/// ViewModel de listing de fichiers : chargement, pagination, mutations optimistes.
@MainActor
@Observable
final class FileGridViewModel {
    private(set) var items: [DriveFile] = []
    private(set) var isInitialLoading = false
    private(set) var isLoadingMore = false
    private(set) var isReloading = false
    private(set) var hasMore = false
    private(set) var totalItemCount: Int?
    var errorMessage: String?
    var mutationErrorMessage: String?
    private(set) var categoriesById: [Int: [FileCategory]] = [:]
    private(set) var itemsRevision = 0

    var source: FileSource
    let driveId: Int
    private let service = KDriveService()

    private var cursor: String?
    private var orderBy: [String]?
    private var order = "asc"
    private var fetchedAt: Date?
    private var dataGeneration = 0
    private(set) var filters = FileFilters()

    var isEmpty: Bool { items.isEmpty }

    init(source: FileSource, driveId: Int) {
        self.source = source
        self.driveId = driveId
    }

    // MARK: Chargement

    func loadIfNeeded() async {
        guard items.isEmpty, !isInitialLoading else { return }

        // 1. Cache mémoire
        if let snapshot = DirectoryListStore.shared.snapshot(driveId: driveId, source: source,
                                                             orderBy: orderBy, order: order) {
            apply(snapshot)
            if Date().timeIntervalSince(snapshot.fetchedAt) < 60 { return }
        }

        isInitialLoading = items.isEmpty
        defer { isInitialLoading = false }
        await reload(forceNetwork: true)
    }

    func reload(sortedBy filters: FileFilters? = nil, forceNetwork: Bool = false) async {
        if let filters { self.filters = filters }
        dataGeneration += 1
        let generation = dataGeneration
        isReloading = true
        defer { if generation == dataGeneration { isReloading = false } }

        do {
            let count = try? await service.directoryCount(driveId: driveId, directoryId: currentDirectoryId)
            let page = try await service.page(source, driveId: driveId, cursor: nil,
                                              orderBy: self.filters.serverOrderBy,
                                              order: self.filters.serverOrder,
                                              forceNetwork: forceNetwork)
            guard generation == dataGeneration else { return }

            let newItems = filterItemsIfNeeded(page.data)
            items = newItems
            cursor = page.cursor
            hasMore = page.hasMore ?? false
            totalItemCount = count?.count ?? page.data.count
            categoriesById = Self.buildCategories(newItems)
            itemsRevision += 1

            storeSnapshot()
        } catch {
            if generation == dataGeneration {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func loadMoreIfNeeded() async {
        guard hasMore, !isLoadingMore, !isReloading, let cursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await service.page(source, driveId: driveId, cursor: cursor,
                                              orderBy: filters.serverOrderBy,
                                              order: filters.serverOrder)
            let existing = Set(items.map(\.id))
            let fresh = page.data.filter { !existing.contains($0.id) }
            items.append(contentsOf: fresh)
            self.cursor = page.cursor
            hasMore = page.hasMore ?? false
            categoriesById.merge(Self.buildCategories(fresh)) { _, new in new }
            itemsRevision += 1
        } catch {
            mutationErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func applyFilters(_ filters: FileFilters) async {
        let previous = self.filters
        self.filters = filters
        if previous.serverOrderBy != filters.serverOrderBy || previous.serverOrder != filters.serverOrder {
            await reload()
        } else {
            items = filterItemsIfNeeded(items)
            itemsRevision += 1
        }
    }

    func visibleItems(searchText: String, mediaMetadata: [Int: MediaMetadataStore.Info]) -> [DriveFile] {
        filters.visible(items, searchText: searchText, mediaMetadata: mediaMetadata)
    }
    // MARK: Cache

    private var currentDirectoryId: Int {
        if case let .directory(id) = source { return id }
        return 1
    }

    private func apply(_ snapshot: DirectoryListSnapshot) {
        items = snapshot.items
        cursor = snapshot.cursor
        hasMore = snapshot.hasMore
        totalItemCount = snapshot.totalItemCount
        orderBy = snapshot.orderBy
        order = snapshot.order
        fetchedAt = snapshot.fetchedAt
        categoriesById = Self.buildCategories(snapshot.items)
        itemsRevision += 1
    }

    private func storeSnapshot() {
        let snapshot = DirectoryListSnapshot(items: items, cursor: cursor, hasMore: hasMore,
                                             totalItemCount: totalItemCount,
                                             orderBy: filters.serverOrderBy,
                                             order: filters.serverOrder,
                                             fetchedAt: Date())
        fetchedAt = snapshot.fetchedAt
        DirectoryListStore.shared.store(snapshot, driveId: driveId, source: source,
                                        orderBy: filters.serverOrderBy, order: filters.serverOrder)
        DirectoryListStore.shared.persist(snapshot, driveId: driveId, source: source,
                                          orderBy: filters.serverOrderBy, order: filters.serverOrder)
    }

    private func filterItemsIfNeeded(_ items: [DriveFile]) -> [DriveFile] {
        if case .recents(_) = source {
            return items.filter { !$0.isDirectory }
        }
        return items
    }

    private static func buildCategories(_ items: [DriveFile]) -> [Int: [FileCategory]] {
        var result: [Int: [FileCategory]] = [:]
        for item in items where !(item.categories ?? []).isEmpty {
            result[item.id] = item.categories
        }
        return result
    }

    // MARK: Mutations optimistes

    func toggleFavorite(_ file: DriveFile) async {
        guard let index = items.firstIndex(where: { $0.id == file.id }) else { return }
        let newValue = !(items[index].isFavorite ?? false)
        items[index] = Self.copy(items[index], isFavorite: newValue)
        itemsRevision += 1
        do {
            try await service.setFavorite(driveId: driveId, fileId: file.id, isFavorite: newValue)
            FileGridMutationCenter.shared.publish(.favorite(driveId: driveId, fileId: file.id, isFavorite: newValue))
        } catch {
            if let index = items.firstIndex(where: { $0.id == file.id }) {
                items[index] = Self.copy(items[index], isFavorite: !newValue)
                itemsRevision += 1
            }
            mutationErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func toggleCategory(_ file: DriveFile, categoryId: Int) async {
        let applied = (file.categories ?? []).contains { $0.categoryId == categoryId }
        let original = file.categories
        var updated = file.categories ?? []
        if applied {
            updated.removeAll { $0.categoryId == categoryId }
        } else {
            updated.append(FileCategory(categoryId: categoryId))
        }
        if let index = items.firstIndex(where: { $0.id == file.id }) {
            items[index] = Self.copy(items[index], categories: updated)
            itemsRevision += 1
        }
        do {
            if applied {
                try await service.removeCategory(driveId: driveId, fileId: file.id, categoryId: categoryId)
            } else {
                try await service.addCategory(driveId: driveId, fileId: file.id, categoryId: categoryId)
            }
            FileGridMutationCenter.shared.publish(.category(driveId: driveId, fileId: file.id,
                                                            categoryId: categoryId, isApplied: !applied))
        } catch {
            if let index = items.firstIndex(where: { $0.id == file.id }) {
                items[index] = Self.copy(items[index], categories: original)
                itemsRevision += 1
            }
            mutationErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func trash(_ file: DriveFile) async {
        let snapshot = items
        removeLocally(ids: [file.id])
        do {
            try await service.trash(driveId: driveId, fileId: file.id)
            FileGridMutationCenter.shared.publish(.removal(driveId: driveId, fileIds: [file.id]))
        } catch {
            items = snapshot
            itemsRevision += 1
            mutationErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func rename(_ file: DriveFile, to newName: String) async {
        let original = file.name
        updateLocally(id: file.id) { Self.copy($0, name: newName) }
        do {
            try await service.rename(driveId: driveId, fileId: file.id, name: newName)
        } catch {
            updateLocally(id: file.id) { Self.copy($0, name: original) }
            mutationErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func setColor(_ file: DriveFile, color: String) async {
        let original = file.color
        updateLocally(id: file.id) { Self.copy($0, color: color) }
        do {
            try await service.setFolderColor(driveId: driveId, fileId: file.id, color: color)
        } catch {
            updateLocally(id: file.id) { Self.copy($0, color: original) }
            mutationErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func move(_ file: DriveFile, to destinationId: Int) async {
        let snapshot = items
        removeLocally(ids: [file.id])
        do {
            try await service.move(driveId: driveId, fileId: file.id, destinationId: destinationId)
            FileGridMutationCenter.shared.publish(.removal(driveId: driveId, fileIds: [file.id]))
        } catch {
            items = snapshot
            itemsRevision += 1
            mutationErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func permanentlyDelete(_ file: DriveFile) async {
        let snapshot = items
        removeLocally(ids: [file.id])
        do {
            try await service.permanentlyDelete(driveId: driveId, fileId: file.id)
            FileGridMutationCenter.shared.publish(.removal(driveId: driveId, fileIds: [file.id]))
        } catch {
            items = snapshot
            itemsRevision += 1
            mutationErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func restore(_ file: DriveFile) async {
        let snapshot = items
        removeLocally(ids: [file.id])
        let destination = file.parentId ?? 1
        do {
            try await service.restore(driveId: driveId, fileId: file.id, destinationId: destination)
        } catch {
            if destination != 1 {
                if (try? await service.restore(driveId: driveId, fileId: file.id, destinationId: 1)) != nil {
                    return
                }
            }
            items = snapshot
            itemsRevision += 1
            mutationErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // Actions de masse

    func trash(ids: [Int]) async {
        let currentDriveId = driveId
        let service = self.service
        await bulk(ids: ids) { fileId in
            try await service.trash(driveId: currentDriveId, fileId: fileId)
        }
    }

    func move(ids: [Int], to destinationId: Int) async {
        let currentDriveId = driveId
        let service = self.service
        await bulk(ids: ids) { fileId in
            try await service.move(driveId: currentDriveId, fileId: fileId, destinationId: destinationId)
        }
    }

    func permanentlyDelete(ids: [Int]) async {
        let currentDriveId = driveId
        let service = self.service
        await bulk(ids: ids) { fileId in
            try await service.permanentlyDelete(driveId: currentDriveId, fileId: fileId)
        }
    }

    func restore(ids: [Int]) async {
        let currentDriveId = driveId
        let service = self.service
        let parents = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.parentId) })
        await bulk(ids: ids) { fileId in
            let destination = (parents[fileId] ?? nil) ?? 1
            try await service.restore(driveId: currentDriveId, fileId: fileId, destinationId: destination)
        }
    }

    private func bulk(ids: [Int], operation: @escaping @Sendable (Int) async throws -> Void) async {
        let snapshot = items
        removeLocally(ids: Set(ids))
        let throttler = AsyncThrottler(maxConcurrent: 4)
        var failures = 0
        await withTaskGroup(of: Bool.self) { group in
            for id in ids {
                group.addTask {
                    do {
                        try await throttler.withPermit { try await operation(id) }
                        return false
                    } catch {
                        return true
                    }
                }
            }
            for await failed in group where failed { failures += 1 }
        }
        FileGridMutationCenter.shared.publish(.removal(driveId: driveId, fileIds: ids))
        if failures > 0 {
            items = snapshot
            itemsRevision += 1
            mutationErrorMessage = "\(failures) opération(s) ont échoué."
        }
    }

    func mergeUploaded(_ files: [DriveFile]) {
        let existing = Set(items.map(\.id))
        let fresh = files.filter { !existing.contains($0.id) }
        guard !fresh.isEmpty else { return }
        items.insert(contentsOf: fresh, at: 0)
        itemsRevision += 1
        DirectoryListStore.shared.mergeRecentUploads(fresh, driveId: driveId)
    }

    private func updateLocally(id: Int, transform: (DriveFile) -> DriveFile) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index] = transform(items[index])
        itemsRevision += 1
    }

    private func removeLocally(ids: Set<Int>) {
        items.removeAll { ids.contains($0.id) }
        itemsRevision += 1
    }

    /// Retrait déclenché par une mutation externe (autre vue/visionneuse).
    func applyExternalRemoval(ids: [Int]) {
        removeLocally(ids: Set(ids))
    }

    /// Applique un changement de tag confirmé ailleurs, sans réseau.
    func applyExternalCategory(fileId: Int, categoryId: Int, isApplied: Bool) {
        if let index = items.firstIndex(where: { $0.id == fileId }) {
            var categories = items[index].categories ?? []
            if isApplied {
                if !categories.contains(where: { $0.categoryId == categoryId }) {
                    categories.append(FileCategory(categoryId: categoryId))
                }
            } else {
                categories.removeAll { $0.categoryId == categoryId }
            }
            items[index] = Self.copy(items[index], categories: categories)
            itemsRevision += 1
        }
        if case let .category(id) = source, id == categoryId, !isApplied {
            removeLocally(ids: [fileId])
        }
    }

    private static func copy(_ file: DriveFile, name: String? = nil, isFavorite: Bool? = nil,
                             categories: [FileCategory]? = nil, color: String? = nil) -> DriveFile {
        DriveFile(id: file.id,
                  name: name ?? file.name,
                  type: file.type,
                  size: file.size,
                  mimeType: file.mimeType,
                  extensionType: file.extensionType,
                  fileExtension: file.fileExtension,
                  isFavorite: isFavorite ?? file.isFavorite,
                  parentId: file.parentId,
                  path: file.path,
                  color: color ?? file.color,
                  categories: categories ?? file.categories,
                  addedAt: file.addedAt,
                  lastModifiedAt: file.lastModifiedAt,
                  updatedAt: file.updatedAt,
                  deletedAt: file.deletedAt)
    }
}

extension FileCategory {
    init(categoryId: Int) {
        self.categoryId = categoryId
        self.isGeneratedByAI = nil
        self.userValidation = nil
        self.userId = nil
        self.addedAt = nil
    }
}
