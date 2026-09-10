import Observation
import SwiftUI
import UIKit

/// Charge en arrière-plan les uploads récents (3 aperçus).
@MainActor
@Observable
final class RecentUploadsLoader {
    static let shared = RecentUploadsLoader()

    private(set) var files: [DriveFile] = []
    private(set) var isLoading = false
    private var lastRefresh: Date?
    private var currentDriveId: Int?
    private let service = KDriveService()
    private let revalidationInterval: TimeInterval = 60

    func cachedSnapshot(driveId: Int) -> [DriveFile] {
        currentDriveId == driveId ? files : []
    }

    func refresh(driveId: Int, forceNetwork: Bool = false) {
        if currentDriveId != driveId {
            currentDriveId = driveId
            files = []
            lastRefresh = nil
        }
        if !forceNetwork, let lastRefresh,
           Date().timeIntervalSince(lastRefresh) < revalidationInterval, !files.isEmpty {
            return
        }
        guard !isLoading else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            if let snapshot = DirectoryListStore.shared.snapshot(
                driveId: driveId, source: .recents(limit: 12), orderBy: nil, order: "asc"), files.isEmpty {
                files = filter(snapshot.items)
            }
            if let page = try? await service.page(.recents(limit: 12), driveId: driveId,
                                                  forceNetwork: forceNetwork) {
                files = filter(page.data)
                lastRefresh = Date()
            }
        }
    }

    func prefetch(forceNetwork: Bool = false) {
        guard let currentDriveId else { return }
        refresh(driveId: currentDriveId, forceNetwork: forceNetwork)
    }

    private func filter(_ items: [DriveFile]) -> [DriveFile] {
        items.filter { !$0.isDirectory }
    }
}

/// Onglet Profil : uploads récents, stockage, à propos.
struct ProfileView: View {
    let session: SessionStore
    let drive: Drive

    @Environment(ViewerRouter.self) private var router
    @Environment(TabNavigationState.self) private var navigation
    @State private var loader = RecentUploadsLoader.shared
    @State private var showTrash = false

    private var previews: [DriveFile] { Array(loader.files.prefix(3)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    recentSection
                    storageSection
                    aboutSection
                }
                .padding(DS.gridMargin)
                .padding(.bottom, 100)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { loader.refresh(driveId: drive.id) }
    }

    private var header: some View {
        HStack(spacing: 14) {
            AppMark(size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(drive.name).font(.headline)
                Text(ByteFormatter.usage(used: drive.usedSize, total: drive.size))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Uploads récents")
                Spacer()
                NavigationLink {
                    RecentFilesView(drive: drive)
                } label: {
                    Text("Tout voir").font(.footnote.weight(.semibold))
                }
            }
            if previews.isEmpty {
                Text(loader.isLoading ? "Chargement…" : "Aucun upload récent")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dsCard()
            } else {
                HStack(spacing: 10) {
                    ForEach(previews) { file in
                        ProfileThumbnailCard(file: file, driveId: drive.id)
                            .onTapGesture { router.open(file, siblings: previews) }
                            .contextMenu {
                                Button {
                                    Task { await FileDownloadService.shared.downloadAndShare(driveId: drive.id, file: file) }
                                } label: { Label("Télécharger", systemImage: "arrow.down.circle") }
                            }
                    }
                }
            }
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Stockage")
            Button { showTrash = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash.fill").foregroundStyle(.red)
                    Text("Corbeille").foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .dsCard()
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showTrash) {
            NavigationStack { TrashView(drive: drive) }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "À propos")
            NavigationLink {
                PerfView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "speedometer").foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading) {
                        Text("Statistiques réseau").foregroundStyle(.primary)
                        Text(versionString).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .dsCard()
            }
            .buttonStyle(.plain)
        }
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Orvian \(version)"
    }
}

/// Aperçu miniature du profil.
struct ProfileThumbnailCard: View {
    let file: DriveFile
    let driveId: Int

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                file.fileKind.tint.opacity(0.12)
                Image(systemName: file.fileKind.symbolName)
                    .font(.title2)
                    .foregroundStyle(file.fileKind.tint)
            }
        }
        .frame(height: 90)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if file.isVideo {
                Image(systemName: "play.fill")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(.black.opacity(0.45), in: Circle())
                    .padding(6)
            }
        }
        .task(id: file.id) { await load() }
    }

    private func load() async {
        if file.fileKind.supportsThumbnail {
            image = await ThumbnailProvider.shared.thumbnail(driveId: driveId, fileId: file.id)
        } else if file.isImage {
            image = await HiresImageStore.shared.image(driveId: driveId, fileId: file.id)
        }
    }
}

/// Liste des fichiers récents.
struct RecentFilesView: View {
    let drive: Drive
    @Environment(ViewerRouter.self) private var router

    var body: some View {
        FileGridView(
            viewModel: FileGridViewModel(source: .recents(limit: 12), driveId: drive.id),
            driveId: drive.id,
            source: .recents(limit: 12),
            onOpenDirectory: { _ in },
            onOpenFile: { file, siblings in router.open(file, siblings: siblings) }
        )
        .navigationTitle("Uploads récents")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Onglet Corbeille.
struct TrashView: View {
    let drive: Drive
    @Environment(ViewerRouter.self) private var router

    var body: some View {
        FileGridView(
            viewModel: FileGridViewModel(source: .trash, driveId: drive.id),
            driveId: drive.id,
            source: .trash,
            onOpenDirectory: { _ in },
            onOpenFile: { file, siblings in router.open(file, siblings: siblings) }
        )
        .navigationTitle("Corbeille")
        .navigationBarTitleDisplayMode(.inline)
    }
}
