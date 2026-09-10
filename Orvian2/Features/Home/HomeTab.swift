import SwiftUI

/// Onglet Accueil : ouvre le premier dossier de la racine.
struct HomeTab: View {
    let session: SessionStore
    let drive: Drive
    let router: ViewerRouter

    @State private var rootDirectory: DriveFile?
    @State private var isResolving = true
    @State private var path = NavigationPath()

    private let service = KDriveService()

    private var startKey: String { "home_start_dir_locked_\(drive.id)" }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let rootDirectory {
                    DirectoryView(
                        driveId: drive.id,
                        source: .directory(rootDirectory.id),
                        rootTitle: rootDirectory.name,
                        allowsPullToRefresh: false,
                        onOpenDirectory: { path.append($0) },
                        onOpenFile: { file, siblings in openViewer(file: file, siblings: siblings) }
                    )
                } else if isResolving {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("Aucun dossier", systemImage: "folder")
                }
            }
            .navigationDestination(for: DriveFile.self) { folder in
                DirectoryView(
                    driveId: drive.id,
                    source: .directory(folder.id),
                    rootTitle: folder.name,
                    onOpenDirectory: { path.append($0) },
                    onOpenFile: { file, siblings in openViewer(file: file, siblings: siblings) }
                )
            }
        }
        .task { await resolveRoot() }
    }

    private func resolveRoot() async {
        if let locked = lockedDirectory {
            rootDirectory = locked
            isResolving = false
        }
        do {
            let page = try await service.page(.directory(1), driveId: drive.id)
            let firstFolder = page.data.first { $0.isDirectory }
            if let firstFolder {
                rootDirectory = firstFolder
                UserDefaults.standard.set(firstFolder.id, forKey: startKey)
                UserDefaults.standard.set(firstFolder.name, forKey: startKey + "_name")
            } else if rootDirectory == nil {
                rootDirectory = DriveFile.root(name: "Accueil")
            }
        } catch {
            if rootDirectory == nil {
                rootDirectory = DriveFile.root(name: "Accueil")
            }
        }
        isResolving = false
    }

    private var lockedDirectory: DriveFile? {
        guard let id = UserDefaults.standard.object(forKey: startKey) as? Int else { return nil }
        let name = UserDefaults.standard.string(forKey: startKey + "_name") ?? "Accueil"
        return DriveFile(id: id, name: name, type: "dir", size: nil, mimeType: nil,
                         extensionType: nil, fileExtension: nil, isFavorite: nil, parentId: 1,
                         path: nil, color: nil, categories: nil, addedAt: nil,
                         lastModifiedAt: nil, updatedAt: nil, deletedAt: nil)
    }

    private func openViewer(file: DriveFile, siblings: [DriveFile]) {
        guard !file.isDirectory else { return }
        router.open(file, siblings: siblings)
    }
}
