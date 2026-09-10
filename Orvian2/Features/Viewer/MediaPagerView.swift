import AVKit
import SwiftUI
import UIKit

/// Visionneuse plein écran unifiée images + vidéos (swipe, zoom, fermeture verticale).
struct MediaPagerView: View {
    let driveId: Int
    let context: MediaViewerContext

    @Environment(\.dismiss) private var dismiss
    @AppStorage("hapticFeedbackEnabled") private var hapticsEnabled = true
    @State private var files: [DriveFile]
    @State private var selectedFileID: Int
    @State private var dragOffset: CGFloat = 0
    @State private var isZoomed = false
    @State private var showCopied = false
    @State private var controlInteractionFileIDs: Set<Int> = []

    private let service = KDriveService()

    init(driveId: Int, context: MediaViewerContext) {
        self.driveId = driveId
        self.context = context
        _files = State(initialValue: context.files)
        let safeIndex = min(max(context.startIndex, 0), max(context.files.count - 1, 0))
        _selectedFileID = State(initialValue: context.files.indices.contains(safeIndex) ? context.files[safeIndex].id : -1)
    }

    private var currentFile: DriveFile? {
        files.first { $0.id == selectedFileID }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedFileID) {
                ForEach(files) { file in
                    page(for: file)
                        .tag(file.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .scrollDisabled(!controlInteractionFileIDs.isEmpty)
            .offset(y: dragOffset)
            .opacity(1 - min(abs(dragOffset) / CGFloat(600), CGFloat(0.6)))

            chrome
        }
        .statusBarHidden()
        .gesture(dismissGesture)
        .task(id: selectedFileID) { await preloadAround(index: files.firstIndex(where: { $0.id == selectedFileID }) ?? 0) }
    }

    @ViewBuilder
    private func page(for file: DriveFile) -> some View {
        Group {
            if file.isVideo {
                VideoPlayerView(
                    driveId: driveId,
                    file: file,
                    isActive: file.id == selectedFileID,
                    onClose: { dismiss() },
                    onInteractionChange: { interacting in
                        if interacting { controlInteractionFileIDs.insert(file.id) }
                        else { controlInteractionFileIDs.remove(file.id) }
                    }
                )
            } else if file.isGIF {
                AnimatedGIFView(driveId: driveId, file: file, isActive: file.id == selectedFileID)
            } else {
                ZoomablePhotoPage(
                    driveId: driveId,
                    file: file,
                    isActive: file.id == selectedFileID,
                    onZoomChange: { isZoomed = $0 }
                )
            }
        }
    }

    private var chrome: some View {
        VStack {
            HStack(spacing: 16) {
                if let file = currentFile {
                    Button {
                        Task { await toggleFavorite(file) }
                    } label: {
                        Image(systemName: file.isFavorite == true ? "star.fill" : "star")
                            .foregroundStyle(file.isFavorite == true ? .yellow : .white)
                    }
                    Image(systemName: "tag")
                        .foregroundStyle(.white)
                }
                Spacer()
                Button {
                    copyTitle()
                } label: {
                    Text(showCopied ? "Copié" : (currentFile?.name ?? ""))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            Spacer()
        }
        .background(
            LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        )
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !isZoomed,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                dragOffset = value.translation.height * 0.55
            }
            .onEnded { value in
                guard !isZoomed else { return }
                if abs(value.translation.height) > 130 {
                    dismiss()
                } else {
                    withAnimation(.snappy) { dragOffset = 0 }
                }
            }
    }

    private func copyTitle() {
        UIPasteboard.general.string = currentFile?.name
        if hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        withAnimation { showCopied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { showCopied = false }
        }
    }

    private func toggleFavorite(_ file: DriveFile) async {
        let newValue = !(file.isFavorite ?? false)
        if let index = files.firstIndex(where: { $0.id == file.id }) {
            files[index] = Self.copy(files[index], isFavorite: newValue)
        }
        try? await service.setFavorite(driveId: driveId, fileId: file.id, isFavorite: newValue)
        FileGridMutationCenter.shared.publish(.favorite(driveId: driveId, fileId: file.id, isFavorite: newValue))
    }

    private func preloadAround(index: Int) async {
        guard files.indices.contains(index) else { return }
        let ids = [index, index + 1].filter { files.indices.contains($0) }
        for id in ids {
            let file = files[id]
            if file.isImage && !file.isGIF {
                ThumbnailProvider.shared.prefetch(driveId: driveId, fileId: file.id)
            }
            if file.isVideo {
                VideoAssetCache.shared.prefetch(driveId: driveId, fileId: file.id)
            }
        }
    }

    private static func copy(_ file: DriveFile, isFavorite: Bool) -> DriveFile {
        DriveFile(id: file.id, name: file.name, type: file.type, size: file.size,
                  mimeType: file.mimeType, extensionType: file.extensionType,
                  fileExtension: file.fileExtension, isFavorite: isFavorite,
                  parentId: file.parentId, path: file.path, color: file.color,
                  categories: file.categories, addedAt: file.addedAt,
                  lastModifiedAt: file.lastModifiedAt, updatedAt: file.updatedAt,
                  deletedAt: file.deletedAt)
    }
}

/// Page photo zoomable (pinch + double-tap).
struct ZoomablePhotoPage: View {
    let driveId: Int
    let file: DriveFile
    let isActive: Bool
    let onZoomChange: (Bool) -> Void

    @State private var thumbnail: UIImage?
    @State private var hires: UIImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = hires ?? thumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(magnify(in: proxy.size))
                        .simultaneousGesture(pan(in: proxy.size))
                        .onTapGesture(count: 2) { toggleZoom(in: proxy.size) }
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onChange(of: scale) { _, value in onZoomChange(value > 1.02) }
        }
        .task(id: file.id) { await load() }
    }

    private func magnify(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(lastScale * value.magnification, 1), 6)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1 { reset() }
                else { offset = clamp(offset, in: size, scale: scale) }
            }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in
                guard scale > 1 else { return }
                offset = clamp(offset, in: size, scale: scale)
                lastOffset = offset
            }
    }

    private func toggleZoom(in size: CGSize) {
        withAnimation(.snappy) {
            if scale > 1 {
                reset()
            } else {
                scale = 2.5
                lastScale = 2.5
            }
        }
    }

    private func reset() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }

    private func clamp(_ value: CGSize, in size: CGSize, scale: CGFloat) -> CGSize {
        let maxX = max(0, (size.width * (scale - 1)) / 2)
        let maxY = max(0, (size.height * (scale - 1)) / 2)
        return CGSize(width: min(max(value.width, -maxX), maxX),
                      height: min(max(value.height, -maxY), maxY))
    }

    private func load() async {
        thumbnail = ThumbnailProvider.cachedMemoryThumbnail(driveId: driveId, fileId: file.id)
        if thumbnail == nil {
            thumbnail = await ThumbnailProvider.shared.thumbnail(driveId: driveId, fileId: file.id)
        }
        let retries: [UInt64] = [0, 3, 8]
        for (attempt, delay) in retries.enumerated() {
            if attempt > 0 { try? await Task.sleep(nanoseconds: delay * 1_000_000_000) }
            if let image = await HiresImageStore.shared.image(driveId: driveId, fileId: file.id) {
                hires = image
                return
            }
        }
    }
}
