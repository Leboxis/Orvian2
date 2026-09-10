import PhotosUI
import SwiftUI

/// Menu de tri et de filtrage.
struct FilterMenu: View {
    @Binding var filters: FileFilters
    let onApply: (FileFilters) -> Void

    var body: some View {
        Menu {
            Menu("Trier par") {
                ForEach(FileFilters.SortMode.allCases) { mode in
                    Button {
                        filters.sort = mode
                        onApply(filters)
                    } label: {
                        Label(mode.label, systemImage: filters.sort == mode ? "checkmark" : "")
                    }
                }
            }
            Menu("Ordre") {
                ForEach(FileFilters.Direction.allCases) { direction in
                    Button {
                        filters.direction = direction
                        onApply(filters)
                    } label: {
                        Label(direction.label, systemImage: filters.direction == direction ? "checkmark" : "")
                    }
                }
            }
            Menu("Orientation vidéo") {
                Button {
                    filters.orientation = nil
                    onApply(filters)
                } label: {
                    Label("Toutes", systemImage: filters.orientation == nil ? "checkmark" : "")
                }
                ForEach(FileFilters.Orientation.allCases) { orientation in
                    Button {
                        filters.orientation = orientation
                        onApply(filters)
                    } label: {
                        Label(orientation.label, systemImage: filters.orientation == orientation ? "checkmark" : "")
                    }
                }
            }
            Toggle("Vidéos 4K et plus", isOn: Binding(
                get: { filters.highResolutionVideosOnly },
                set: { filters.highResolutionVideosOnly = $0; filters.media = $0 ? .videos : filters.media; onApply(filters) }
            ))
            Menu("Afficher") {
                ForEach(FileFilters.MediaFilter.allCases) { media in
                    Button {
                        filters.media = media
                        onApply(filters)
                    } label: {
                        Label(media.label, systemImage: filters.media == media ? "checkmark" : "")
                    }
                }
            }
            Divider()
            Button(role: .destructive) {
                filters = FileFilters()
                onApply(filters)
            } label: {
                Label("Réinitialiser", systemImage: "arrow.counterclockwise")
            }
        } label: {
            Image(systemName: filters.isActive ? "line.3.horizontal.decrease.circle.fill"
                                               : "line.3.horizontal.decrease.circle")
        }
    }
}

/// Menu d'ajout : dossier, photos, fichiers.
struct AddMenuButton: View {
    let driveId: Int
    let directoryId: Int
    let onCreated: () -> Void

    @State private var showFolderPrompt = false
    @State private var folderName = ""
    @State private var showPhotos = false
    @State private var showDocuments = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isImporting = false

    private let service = KDriveService()

    var body: some View {
        Menu {
            Button { showFolderPrompt = true } label: {
                Label("Nouveau dossier", systemImage: "folder.badge.plus")
            }
            Button { showPhotos = true } label: {
                Label("Importer photos & vidéos", systemImage: "photo.on.rectangle")
            }
            Button { showDocuments = true } label: {
                Label("Importer des fichiers", systemImage: "doc.badge.plus")
            }
        } label: {
            Image(systemName: "plus")
                .font(.headline)
        }
        .alert("Nouveau dossier", isPresented: $showFolderPrompt) {
            TextField("Nom", text: $folderName)
            Button("Annuler", role: .cancel) { folderName = "" }
            Button("Créer") {
                let name = folderName
                folderName = ""
                Task {
                    _ = try? await service.createFolder(driveId: driveId, directoryId: directoryId, name: name)
                    onCreated()
                }
            }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItems,
                      maxSelectionCount: 20, matching: .any(of: [.images, .videos]))
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .sheet(isPresented: $showDocuments) {
            DocumentPicker { urls in
                Task { await importDocuments(urls) }
            }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        isImporting = true
        var payloads: [UploadManager.UploadPayload] = []
        for (index, item) in items.enumerated() {
            if let transferable = try? await item.loadTransferable(type: PickedPhotoTransferable.self) {
                let name = transferable.fileName.isEmpty
                    ? "Média \(index + 1).\(transferable.fileExtension)"
                    : transferable.fileName
                payloads.append(.init(fileURL: transferable.url, fileName: name,
                                      totalBytes: transferable.totalBytes, isTemporary: true))
            }
        }
        photoItems = []
        isImporting = false
        UploadManager.shared.enqueuePhotos(driveId: driveId, directoryId: directoryId, items: payloads)
        onCreated()
    }

    private func importDocuments(_ urls: [URL]) async {
        let payloads = urls.map { url -> UploadManager.UploadPayload in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0
            return .init(fileURL: url, fileName: url.lastPathComponent, totalBytes: size, isTemporary: false)
        }
        UploadManager.shared.enqueueDocuments(driveId: driveId, directoryId: directoryId, payloads: payloads)
        onCreated()
    }
}

/// Applique des tags à une sélection (états none/partial/all).
struct ApplyTagsSheet: View {
    let files: [DriveFile]
    let driveId: Int
    let viewModel: FileGridViewModel
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var library = CategoryLibrary.shared
    @State private var isWorking = false
    @State private var errorText: String?

    private let service = KDriveService()

    private var categories: [Category] { library.categories(for: driveId) }

    var body: some View {
        NavigationStack {
            List {
                if categories.isEmpty {
                    Text("Aucun tag disponible.").foregroundStyle(.secondary)
                } else {
                    ForEach(categories) { category in
                        Button {
                            Task { await apply(category) }
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(hex: category.color ?? "") ?? CategoryPalette.color(for: category.id))
                                    .frame(width: 12, height: 12)
                                Text(category.name).foregroundStyle(.primary)
                                Spacer()
                                stateIcon(for: category.id)
                            }
                        }
                        .disabled(isWorking)
                    }
                }
                if let errorText {
                    Text(errorText).font(.caption).foregroundStyle(.red)
                }
            }
            .navigationTitle("Appliquer des tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .task { await library.ensureLoaded(driveId: driveId) }
        }
    }

    @ViewBuilder
    private func stateIcon(for categoryId: Int) -> some View {
        let counts = files.filter { file in
            (viewModel.items.first { $0.id == file.id }?.categories ?? file.categories ?? [])
                .contains { $0.categoryId == categoryId }
        }.count
        if counts == files.count {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
        } else if counts == 0 {
            Image(systemName: "circle").foregroundStyle(.tertiary)
        } else {
            Image(systemName: "minus.circle.fill").foregroundStyle(.orange)
        }
    }

    private func apply(_ category: Category) async {
        isWorking = true
        defer { isWorking = false }
        let target = files
        let appliedCount = target.filter { file in
            (viewModel.items.first { $0.id == file.id }?.categories ?? file.categories ?? [])
                .contains { $0.categoryId == category.id }
        }.count
        let shouldAdd = appliedCount < target.count

        let results = (try? await mapBounded(target, concurrency: 4) { file -> Bool in
            do {
                if shouldAdd {
                    try await service.addCategory(driveId: driveId, fileId: file.id, categoryId: category.id)
                } else {
                    try await service.removeCategory(driveId: driveId, fileId: file.id, categoryId: category.id)
                }
                return false
            } catch {
                return true
            }
        }) ?? []

        let failures = results.filter { $0 }.count
        if failures > 0 {
            errorText = "\(failures) opération(s) ont échoué."
        } else {
            for file in target {
                FileGridMutationCenter.shared.publish(.category(driveId: driveId, fileId: file.id,
                                                               categoryId: category.id, isApplied: shouldAdd))
            }
            onDone()
            dismiss()
        }
    }
}

/// Sélecteur de dossier de destination (navigation arborescente).
struct MoveDestinationPicker: View {
    let driveId: Int
    let excludingIDs: Set<Int>
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: FileGridViewModel
    @State private var path: [(id: Int, name: String)] = []

    private let service = KDriveService()

    init(driveId: Int, excludingIDs: Set<Int>, onSelect: @escaping (Int) -> Void) {
        self.driveId = driveId
        self.excludingIDs = excludingIDs
        self.onSelect = onSelect
        _viewModel = State(initialValue: FileGridViewModel(source: .directory(1), driveId: driveId))
    }

    var body: some View {
        NavigationStack {
            List {
                if let current = path.last {
                    Button {
                        onSelect(current.id)
                        dismiss()
                    } label: {
                        Label("Choisir « \(current.name) »", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                } else {
                    Button {
                        onSelect(1)
                        dismiss()
                    } label: {
                        Label("Choisir « Racine du drive »", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Section("Dossiers") {
                    ForEach(folders) { folder in
                        Button {
                            path.append((folder.id, folder.name))
                            viewModel = FileGridViewModel(source: .directory(folder.id), driveId: driveId)
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(folder.fileKind.tint)
                                Text(folder.name)
                            }
                        }
                    }
                }
            }
            .navigationTitle(path.last?.name ?? "Racine du drive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if path.isEmpty {
                        Button("Annuler") { dismiss() }
                    } else {
                        Button("Retour") { _ = path.popLast() }
                    }
                }
            }
            .task { await viewModel.loadIfNeeded() }
        }
    }

    private var folders: [DriveFile] {
        viewModel.items.filter { $0.isDirectory && !excludingIDs.contains($0.id) }
    }
}

/// Menu d'actions de sélection multiple.
struct SelectionActionBar: View {
    let count: Int
    let isTrash: Bool
    let onSelectAll: () -> Void
    let onTags: () -> Void
    let onMove: (() -> Void)?
    let onDelete: () -> Void
    let onRestore: (() -> Void)?

    var body: some View {
        HStack(spacing: 22) {
            Button(action: onSelectAll) {
                Label("Tout", systemImage: "checkmark.circle")
            }
            if isTrash {
                if let onRestore {
                    Button(action: onRestore) { Label("Restaurer", systemImage: "arrow.uturn.backward") }
                }
            } else {
                Button(action: onTags) { Label("Tag", systemImage: "tag") }
                if let onMove {
                    Button(action: onMove) { Label("Déplacer", systemImage: "folder") }
                }
            }
            Button(role: .destructive, action: onDelete) {
                Label("Supprimer", systemImage: "trash")
            }
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
    }
}
