import SwiftUI

/// Onglet Favoris : navigation dans les dossiers favoris.
struct FavoritesView: View {
    let drive: Drive
    let isActive: Bool

    @Environment(ViewerRouter.self) private var router
    @Environment(TabNavigationState.self) private var navigation
    @State private var path = NavigationPath()
    @State private var filters = FileFilters()
    @State private var viewModel: FileGridViewModel

    init(drive: Drive, isActive: Bool) {
        self.drive = drive
        self.isActive = isActive
        _viewModel = State(initialValue: FileGridViewModel(source: .favorites(limit: 60), driveId: drive.id))
    }

    var body: some View {
        NavigationStack(path: $path) {
            FileGridView(
                viewModel: viewModel,
                driveId: drive.id,
                source: .favorites(limit: 60),
                filters: filters,
                allowsPullToRefresh: true,
                scrollToTopRequest: navigation.favoritesScrollToTopRequest,
                onOpenDirectory: { path.append($0) },
                onOpenFile: { file, siblings in router.open(file, siblings: siblings) },
                showsFavoriteBadge: false
            )
            .navigationTitle("Favoris")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    FilterMenu(filters: $filters) { newFilters in
                        Task { await viewModel.applyFilters(newFilters) }
                    }
                }
            }
            .navigationDestination(for: DriveFile.self) { folder in
                FileGridView(
                    viewModel: FileGridViewModel(source: .directory(folder.id), driveId: drive.id),
                    driveId: drive.id,
                    source: .directory(folder.id),
                    onOpenDirectory: { path.append($0) },
                    onOpenFile: { file, siblings in router.open(file, siblings: siblings) },
                    showsFavoriteBadge: false
                )
                .navigationTitle(folder.name)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .onChange(of: navigation.favoritesScrollToTopRequest) { _, _ in
            path = NavigationPath()
        }
    }
}
