import Observation
import SwiftUI

/// État de navigation par onglet (chemins de NavigationStack).
@MainActor
@Observable
final class TabNavigationState {
    var homePath = NavigationPath()
    var favoritesPath = NavigationPath()
    var favoritesScrollToTopRequest = 0
    var tagsPath = NavigationPath()
    var profilePath = NavigationPath()
    var profileRefreshRequest = 0

    func reset(tab: AppTab, scrollFavoritesToTop: Bool = false) {
        switch tab {
        case .home: homePath = NavigationPath()
        case .favorites:
            favoritesPath = NavigationPath()
            if scrollFavoritesToTop { favoritesScrollToTopRequest += 1 }
        case .tags: tagsPath = NavigationPath()
        case .profile: profilePath = NavigationPath()
        case .settings: break
        }
    }
}

/// Contexte de la visionneuse média.
struct MediaViewerContext: Identifiable {
    let id = UUID()
    let driveId: Int
    let filters: FileFilters
    let searchText: String
    let files: [DriveFile]
    let startIndex: Int
}

/// Fichier texte ouvert dans le lecteur.
struct TextFileContext: Identifiable {
    let id = UUID()
    let driveId: Int
    let file: DriveFile
}

/// Routeur global des visionneuses.
@MainActor
@Observable
final class ViewerRouter {
    var mediaContext: MediaViewerContext?
    var textFile: TextFileContext?

    func open(_ file: DriveFile, siblings: [DriveFile],
              filters: FileFilters = FileFilters(), searchText: String = "") {
        guard !file.isDirectory else { return }
        if file.isImage || file.isVideo {
            let media = siblings.filter { $0.isImage || $0.isVideo }
            let index = media.firstIndex(where: { $0.id == file.id }) ?? 0
            mediaContext = MediaViewerContext(driveId: 0, filters: filters, searchText: searchText,
                                              files: media, startIndex: index)
        } else {
            textFile = TextFileContext(driveId: 0, file: file)
        }
    }
}
