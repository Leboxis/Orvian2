import Combine
import SwiftUI

/// Grille de fichiers réutilisable (Accueil, Favoris, Tag, Corbeille).
struct FileGridView: View {
    @Bindable var viewModel: FileGridViewModel
    let driveId: Int
    let source: FileSource
    var searchText: String = ""
    var filters: FileFilters = FileFilters()
    var contentTopInset: CGFloat = 0
    var allowsPullToRefresh = true
    var selectionMode = false
    var selectedIDs: Set<Int> = []
    var scrollToTopRequest = 0

    var onOpenDirectory: (DriveFile) -> Void
    var onOpenFile: (DriveFile, [DriveFile]) -> Void
    var onVisibleItemsChanged: (([DriveFile]) -> Void)? = nil
    var onToggleSelection: ((DriveFile) -> Void)? = nil
    var onMove: ((DriveFile) -> Void)? = nil
    var onResetFilters: (() -> Void)? = nil
    var showsFavoriteBadge = true

    @AppStorage("fileGridColumns") private var fileGridColumns = 3
    @AppStorage("prefetchThumbnails") private var prefetchThumbnails = true
    @AppStorage("prefetchVideoURLs") private var prefetchVideoURLs = true
    @AppStorage("prefetchOnWiFiOnly") private var prefetchOnWiFiOnly = false

    @State private var mediaMetadata = MediaMetadataStore.shared
    @State private var detailRequest: DriveFile?
    @State private var tagsRequest: DriveFile?
    @State private var colorRequest: DriveFile?
    @State private var renameRequest: DriveFile?
    @State private var deleteRequest: DriveFile?
    @State private var presentedFileIDs: Set<Int> = []

    private var columns: [GridItem] {
        let count = min(max(fileGridColumns, 2), 7)
        return Array(repeating: GridItem(.flexible(), spacing: DS.gridSpacing), count: count)
    }

    private var visibleItems: [DriveFile] {
        viewModel.visibleItems(searchText: searchText, mediaMetadata: mediaMetadata.allInfo)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: contentTopInset)
                    .id("file-grid-top")
                LazyVGrid(columns: columns, spacing: DS.gridSpacing) {
                    if viewModel.isInitialLoading && viewModel.isEmpty {
                        ForEach(0..<9, id: \.self) { _ in
                            SkeletonView().aspectRatio(1, contentMode: .fit)
                        }
                    } else {
                        ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, file in
                            FileCardView(
                                file: file,
                                driveId: driveId,
                                isSelectionMode: selectionMode,
                                isSelected: selectedIDs.contains(file.id),
                                showsFavoriteBadge: showsFavoriteBadge && !isFavoritesSource,
                                onTap: { open(file) },
                                onToggleSelection: { onToggleSelection?(file) }
                            )
                            .contextMenu { contextMenu(for: file) }
                            .onAppear { onCardAppear(index: index, file: file) }
                        }
                    }
                }
                .padding(.horizontal, DS.gridMargin)

                if !viewModel.isEmpty && visibleItems.isEmpty {
                    filteredEmptyState
                } else if viewModel.isEmpty && !viewModel.isInitialLoading {
                    emptyState
                }

                if viewModel.isLoadingMore {
                    ProgressView().padding(.vertical, 16)
                }

                Color.clear.frame(height: 110)
            }
            .refreshable { if allowsPullToRefresh { await viewModel.reload(forceNetwork: true) } }
            .onChange(of: scrollToTopRequest) { _, _ in
                withAnimation { proxy.scrollTo("file-grid-top", anchor: .top) }
            }
            .onChange(of: visibleItems.map(\.id)) { _, ids in
                onVisibleItemsChanged?(visibleIds(ids))
                refreshPresentedFiles()
            }
        }
        .sheet(item: $detailRequest) { file in
            FileDetailSheet(file: currentFile(matching: file), driveId: driveId, viewModel: viewModel,
                            source: source, onOpen: { open($0) })
        }
        .sheet(item: $tagsRequest) { file in
            TagsEditorSheet(file: currentFile(matching: file), driveId: driveId, viewModel: viewModel)
        }
        .sheet(item: $colorRequest) { file in
            FolderColorPickerSheet(file: currentFile(matching: file), viewModel: viewModel)
        }
        .alert("Renommer", isPresented: Binding(
            get: { renameRequest != nil },
            set: { if !$0 { renameRequest = nil } }
        )) {
            TextField("Nom", text: renameTextBinding)
            Button("Annuler", role: .cancel) { renameRequest = nil }
            Button("Renommer") {
                if let file = renameRequest {
                    Task { await viewModel.rename(file, to: renameText) }
                }
                renameRequest = nil
            }
        }
        .confirmationDialog("Supprimer", isPresented: Binding(
            get: { deleteRequest != nil },
            set: { if !$0 { deleteRequest = nil } }
        ), titleVisibility: .visible) {
            if isTrashSource {
                Button("Supprimer définitivement", role: .destructive) {
                    if let file = deleteRequest { Task { await viewModel.permanentlyDelete(file) } }
                    deleteRequest = nil
                }
            } else {
                Button("Mettre à la corbeille", role: .destructive) {
                    if let file = deleteRequest { Task { await viewModel.trash(file) } }
                    deleteRequest = nil
                }
            }
            Button("Annuler", role: .cancel) { deleteRequest = nil }
        } message: {
            Text(deleteRequest?.name ?? "")
        }
        .alert("Erreur", isPresented: Binding(
            get: { viewModel.mutationErrorMessage != nil },
            set: { if !$0 { viewModel.mutationErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.mutationErrorMessage ?? "")
        }
        .task { await viewModel.loadIfNeeded() }
        .onChange(of: filters) { _, _ in
            if filtersRequireMetadata {
                Task { await mediaMetadata.resolveAll(driveId: driveId, items: viewModel.items) }
            }
        }
        .onReceive(FileGridMutationCenter.shared.mutations
            .filter { $0.driveId == driveId }
            .receive(on: RunLoop.main)) { mutation in
                handleMutation(mutation)
            }
    }

    private func handleMutation(_ mutation: FileGridMutation) {
        switch mutation {
        case .removal(_, let fileIds):
            viewModel.applyExternalRemoval(ids: fileIds)
            refreshPresentedFiles()
        case .uploaded:
            Task { await viewModel.reload(forceNetwork: true) }
        case .favorite:
            Task { await viewModel.reload() }
        case let .category(_, fileId, categoryId, isApplied):
            viewModel.applyExternalCategory(fileId: fileId, categoryId: categoryId, isApplied: isApplied)
        }
    }

    // MARK: Context menu

    @ViewBuilder
    private func contextMenu(for file: DriveFile) -> some View {
        if !selectionMode {
            Button { detailRequest = file } label: { Label("Détails", systemImage: "info.circle") }
            if file.isDirectory {
                Button { colorRequest = file } label: { Label("Changer la couleur", systemImage: "paintpalette") }
            } else {
                Button {
                    Task { await FileDownloadService.shared.downloadAndShare(driveId: driveId, file: file) }
                } label: { Label("Télécharger", systemImage: "arrow.down.circle") }
            }
            Button { tagsRequest = file } label: { Label("Tags", systemImage: "tag") }
            Button {
                Task { await viewModel.toggleFavorite(file) }
            } label: {
                Label(file.isFavorite == true ? "Retirer des favoris" : "Favori",
                      systemImage: file.isFavorite == true ? "star.slash" : "star")
            }
            Button { startRename(file) } label: { Label("Renommer", systemImage: "pencil") }
            if !isTrashSource {
                Button { onMove?(file) } label: { Label("Déplacer", systemImage: "folder") }
                Button(role: .destructive) { deleteRequest = file } label: { Label("Supprimer", systemImage: "trash") }
            } else {
                Button(role: .destructive) { deleteRequest = file } label: { Label("Supprimer", systemImage: "trash") }
            }
        }
    }

    // MARK: Empty states

    @ViewBuilder
    private var emptyState: some View {
        switch source {
        case .trash:
            EmptyStateView(title: "Corbeille vide", systemImage: "trash")
        case .favorites(_):
            EmptyStateView(title: "Aucun favori", systemImage: "star")
        case .recents(_):
            EmptyStateView(title: "Aucun upload récent", systemImage: "clock")
        case .category(_):
            EmptyStateView(title: "Aucun fichier avec ce tag", systemImage: "tag")
        case .search(_, _):
            EmptyStateView(title: "Aucun résultat", systemImage: "magnifyingglass")
        case .directory(_):
            EmptyStateView(title: "Dossier vide", systemImage: "folder")
        }
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 14) {
            ContentUnavailableView {
                Label("Aucun résultat", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Aucun élément ne correspond au filtre ou à la recherche.")
            }
            Button("Réinitialiser les filtres") {
                if let onResetFilters {
                    onResetFilters()
                } else {
                    Task { await viewModel.applyFilters(FileFilters()) }
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 60)
    }

    // MARK: Actions

    @State private var renameText = ""

    private func startRename(_ file: DriveFile) {
        renameText = file.name
        renameRequest = file
    }

    private var renameTextBinding: Binding<String> {
        Binding(get: { renameText }, set: { renameText = $0 })
    }

    private func open(_ file: DriveFile) {
        if file.isDirectory {
            onOpenDirectory(file)
        } else {
            onOpenFile(file, visibleItems)
        }
    }

    private func onCardAppear(index: Int, file: DriveFile) {
        if index >= visibleItems.count - 6 {
            Task { await viewModel.loadMoreIfNeeded() }
        }
        prefetch(after: index)
    }

    private func prefetch(after index: Int) {
        guard prefetchThumbnails || prefetchVideoURLs else { return }
        if prefetchOnWiFiOnly && !NetworkMonitor.shared.allowsBackgroundPrefetch { return }
        let upcoming = visibleItems.dropFirst(index + 1).prefix(3)
        for file in upcoming {
            if prefetchThumbnails && file.fileKind.supportsThumbnail {
                Task { await ThumbnailProvider.shared.prefetch(driveId: driveId, fileId: file.id,
                                                               isTrashed: isTrashSource) }
            }
            if prefetchVideoURLs && file.isVideo && !isTrashSource {
                VideoAssetCache.shared.prefetch(driveId: driveId, fileId: file.id)
            }
        }
        if filtersRequireMetadata {
            Task { await mediaMetadata.resolveAll(driveId: driveId, items: visibleItems) }
        }
    }

    private var filtersRequireMetadata: Bool {
        filters.orientation != nil || filters.highResolutionVideosOnly
    }

    private func visibleIds(_ ids: [Int]) -> [DriveFile] {
        let lookup = Dictionary(uniqueKeysWithValues: visibleItems.map { ($0.id, $0) })
        return ids.compactMap { lookup[$0] }
    }

    private func refreshPresentedFiles() {
        // Ferme les présentations dont le fichier a disparu.
        detailRequest = refreshIfNeeded(detailRequest)
        tagsRequest = refreshIfNeeded(tagsRequest)
        colorRequest = refreshIfNeeded(colorRequest)
    }

    private func refreshIfNeeded(_ file: DriveFile?) -> DriveFile? {
        guard let file else { return nil }
        return visibleItems.contains { $0.id == file.id } ? file : nil
    }

    private func currentFile(matching file: DriveFile) -> DriveFile {
        visibleItems.first { $0.id == file.id } ?? file
    }

    private var isFavoritesSource: Bool {
        if case .favorites(_) = source { return true }
        return false
    }
    private var isTrashSource: Bool {
        if case .trash = source { return true }
        return false
    }
}
