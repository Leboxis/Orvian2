import SwiftUI

/// Vue de navigation dans les dossiers, réutilisée par Accueil, Favoris et Tag.
struct DirectoryView: View {
    let driveId: Int
    let source: FileSource
    var rootTitle: String = "Racine"
    var allowsPullToRefresh = true
    var alwaysShowSearch = false
    var showsFavoriteBadge = true
    var scrollToTopRequest = 0
    var selectionEnabled = true
    let onOpenDirectory: (DriveFile) -> Void
    var onOpenFile: ((DriveFile, [DriveFile]) -> Void)?

    @AppStorage("alwaysShowSearch") private var alwaysShowSearchSetting = false
    @State private var viewModel: FileGridViewModel
    @State private var searchText = ""
    @State private var filters = FileFilters()
    @State private var debouncedSearch = ""
    @State private var searchTask: Task<Void, Never>?

    @State private var isSelecting = false
    @State private var selectedIDs: Set<Int> = []
    @State private var moveRequest: [DriveFile] = []
    @State private var showApplyTags = false
    @State private var randomOpen: DriveFile?

    init(driveId: Int, source: FileSource, rootTitle: String = "Racine",
         allowsPullToRefresh: Bool = true, alwaysShowSearch: Bool = false,
         showsFavoriteBadge: Bool = true, scrollToTopRequest: Int = 0,
         selectionEnabled: Bool = true,
         onOpenDirectory: @escaping (DriveFile) -> Void,
         onOpenFile: ((DriveFile, [DriveFile]) -> Void)? = nil) {
        self.driveId = driveId
        self.source = source
        self.rootTitle = rootTitle
        self.allowsPullToRefresh = allowsPullToRefresh
        self.alwaysShowSearch = alwaysShowSearch
        self.showsFavoriteBadge = showsFavoriteBadge
        self.scrollToTopRequest = scrollToTopRequest
        self.selectionEnabled = selectionEnabled
        self.onOpenDirectory = onOpenDirectory
        self.onOpenFile = onOpenFile
        _viewModel = State(initialValue: FileGridViewModel(source: source, driveId: driveId))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            FileGridView(
                viewModel: viewModel,
                driveId: driveId,
                source: source,
                searchText: debouncedSearch,
                filters: filters,
                contentTopInset: 4,
                allowsPullToRefresh: allowsPullToRefresh,
                selectionMode: isSelecting,
                selectedIDs: selectedIDs,
                scrollToTopRequest: scrollToTopRequest,
                onOpenDirectory: onOpenDirectory,
                onOpenFile: { file, siblings in onOpenFile?(file, siblings) },
                onToggleSelection: { toggleSelection($0) },
                onMove: { moveRequest = [$0] },
                onResetFilters: {
                    filters = FileFilters()
                    Task { await viewModel.applyFilters(filters) }
                },
                showsFavoriteBadge: showsFavoriteBadge
            )

            if !isSelecting {
                AddMenuButton(driveId: driveId, directoryId: currentDirectoryId) {
                    Task { await viewModel.reload(forceNetwork: true) }
                }
                .frame(width: 54, height: 54)
                .background(Color.accentColor, in: Circle())
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                .padding(.trailing, DS.gridMargin + 2)
                .padding(.bottom, 120)
                .accessibilityLabel("Ajouter")
            }

            if isSelecting && !selectedIDs.isEmpty {
                SelectionActionBar(
                    count: selectedIDs.count,
                    isTrash: isTrashSource,
                    onSelectAll: { selectedIDs = Set(viewModel.items.map(\.id)) },
                    onTags: { showApplyTags = true },
                    onMove: isTrashSource ? nil : { moveRequest = selectedFiles },
                    onDelete: {
                        if isTrashSource {
                            Task { await viewModel.permanentlyDelete(ids: Array(selectedIDs)); exitSelection() }
                        } else {
                            Task { await viewModel.trash(ids: Array(selectedIDs)); exitSelection() }
                        }
                    },
                    onRestore: isTrashSource ? {
                        Task { await viewModel.restore(ids: Array(selectedIDs)); exitSelection() }
                    } : nil
                )
                .padding(.bottom, 120)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(rootTitle)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: alwaysShowSearchSetting || alwaysShowSearch ? .always : .automatic),
                    prompt: "Rechercher")
        .onChange(of: searchText) { _, value in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                debouncedSearch = value
            }
        }
        .toolbar { toolbarContent }
        .sheet(isPresented: $showApplyTags) {
            ApplyTagsSheet(files: selectedFiles, driveId: driveId, viewModel: viewModel) {
                exitSelection()
            }
        }
        .sheet(item: Binding(get: { moveRequest.first }, set: { if $0 == nil { moveRequest = [] } })) { file in
            MoveDestinationPicker(driveId: driveId,
                                  excludingIDs: Set(selectedFiles.map(\.id))) { destination in
                Task {
                    if selectedFiles.count > 1 {
                        await viewModel.move(ids: Array(selectedIDs), to: destination)
                    } else {
                        await viewModel.move(file, to: destination)
                    }
                    exitSelection()
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            FilterMenu(filters: $filters) { newFilters in
                Task { await viewModel.applyFilters(newFilters) }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if isSelecting {
                Button("Annuler") { exitSelection() }
            } else if selectionEnabled {
                Menu {
                    Button {
                        isSelecting = true
                    } label: {
                        Label("Sélectionner", systemImage: "checkmark.circle")
                    }
                    Button {
                        openRandom()
                    } label: {
                        Label("Ouvrir un élément au hasard", systemImage: "dice")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: Actions

    private var selectedFiles: [DriveFile] {
        viewModel.items.filter { selectedIDs.contains($0.id) }
    }

    private func toggleSelection(_ file: DriveFile) {
        if selectedIDs.contains(file.id) {
            selectedIDs.remove(file.id)
        } else {
            selectedIDs.insert(file.id)
        }
    }

    private func exitSelection() {
        isSelecting = false
        selectedIDs.removeAll()
    }

    private func openRandom() {
        guard let file = viewModel.items.randomElement() else { return }
        if file.isDirectory {
            onOpenDirectory(file)
        } else {
            onOpenFile?(file, viewModel.items)
        }
    }

    private var currentDirectoryId: Int {
        if case let .directory(id) = source { return id }
        return 1
    }

    private var isTrashSource: Bool {
        if case .trash = source { return true }
        return false
    }
}
