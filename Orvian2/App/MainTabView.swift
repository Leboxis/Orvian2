import SwiftUI

/// Conteneur principal : onglets flottants + bannières de transfert.
struct MainTabView: View {
    let session: SessionStore
    let drive: Drive

    @State private var selection: AppTab = .home
    @State private var navigation = TabNavigationState()
    @State private var router = ViewerRouter()
    @State private var uploads = UploadManager.shared
    @ObservedObject private var downloads = FileDownloadService.shared
    @State private var visited: Set<AppTab> = [.home]

    var body: some View {
        ZStack(alignment: .bottom) {
            tabContent
                .ignoresSafeArea(.keyboard, edges: .bottom)

            VStack(spacing: 8) {
                if downloads.isDownloading {
                    DownloadProgressBanner()
                }
                if uploads.isPillVisible {
                    UploadProgressPill()
                }
                FloatingTabBar(
                    selection: selection,
                    onSelect: { select($0) },
                    onReselect: { reselect($0) }
                )
            }
            .padding(.bottom, 4)
        }
        .fullScreenCover(item: $router.mediaContext) { context in
            MediaPagerView(driveId: drive.id, context: context)
        }
        .fullScreenCover(item: $router.textFile) { context in
            TextFileViewer(driveId: drive.id, file: context.file)
        }
        .alert("Téléchargement", isPresented: Binding(
            get: { downloads.errorMessage != nil },
            set: { if !$0 { downloads.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(downloads.errorMessage ?? "")
        }
        .environment(navigation)
        .environment(router)
    }

    @ViewBuilder
    private var tabContent: some View {
        // Seul Accueil reste monté en permanence ; les autres onglets sont recréés.
        ZStack {
            HomeTab(session: session, drive: drive, router: router)
                .opacity(selection == .home ? 1 : 0)
                .allowsHitTesting(selection == .home)
                .zIndex(selection == .home ? 1 : 0)

            if visited.contains(.favorites) {
                FavoritesView(drive: drive, isActive: selection == .favorites)
                    .opacity(selection == .favorites ? 1 : 0)
                    .allowsHitTesting(selection == .favorites)
            }
            if visited.contains(.tags) {
                TagsView(session: session, drive: drive)
                    .opacity(selection == .tags ? 1 : 0)
                    .allowsHitTesting(selection == .tags)
            }
            if visited.contains(.settings) {
                SettingsView(session: session, drive: drive)
                    .opacity(selection == .settings ? 1 : 0)
                    .allowsHitTesting(selection == .settings)
            }
            if visited.contains(.profile) {
                ProfileView(session: session, drive: drive)
                    .opacity(selection == .profile ? 1 : 0)
                    .allowsHitTesting(selection == .profile)
            }
        }
    }

    private func select(_ tab: AppTab) {
        visited.insert(tab)
        withAnimation(.snappy(duration: 0.22)) { selection = tab }
        if tab == .profile { RecentUploadsLoader.shared.prefetch() }
    }

    private func reselect(_ tab: AppTab) {
        let scrollToTop = UserDefaults.standard.object(forKey: "favoritesReselectScrollToTop") as? Bool ?? true
        navigation.reset(tab: tab, scrollFavoritesToTop: scrollToTop)
        if tab == .profile { RecentUploadsLoader.shared.prefetch(forceNetwork: true) }
    }
}

/// Bannière de progression de téléchargement.
struct DownloadProgressBanner: View {
    @ObservedObject private var downloads = FileDownloadService.shared

    var body: some View {
        HStack(spacing: 12) {
            ProgressView(value: downloads.progress)
                .progressViewStyle(.circular)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(downloads.downloadingFileName ?? "Téléchargement")
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                Text("\(Int(downloads.progress * 100)) %")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Annuler") { downloads.cancelDownload() }
                .font(.footnote.weight(.semibold))
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
        .padding(.horizontal, DS.gridMargin + 8)
    }
}
