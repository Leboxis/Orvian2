import SwiftUI
import UIKit

/// Carte carrée stricte réutilisable dans les grilles.
struct FileCardView: View {
    let file: DriveFile
    let driveId: Int
    let isSelectionMode: Bool
    let isSelected: Bool
    let showsFavoriteBadge: Bool
    let onTap: () -> Void
    let onToggleSelection: () -> Void

    @AppStorage("showFileSizes") private var showFileSizes = true
    @AppStorage("fileGridColumns") private var fileGridColumns = 3
    @Environment(\.colorScheme) private var colorScheme

    @State private var thumbnail: UIImage?
    @State private var isLoadingThumbnail = false

    private var kind: FileKind { file.fileKind }
    private var folderTint: Color {
        if let hex = file.color, let color = Color(hex: hex) { return color }
        if let hex = UserDefaults.standard.string(forKey: "defaultFolderColor"), let color = Color(hex: hex) { return color }
        return kind.tint
    }
    private var cardTint: Color { file.isDirectory ? folderTint : kind.tint }

    var body: some View {
        Button(action: {
            if isSelectionMode { onToggleSelection() } else { onTap() }
        }) {
            VStack(spacing: 6) {
                ZStack {
                    cardContent
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
                .overlay(alignment: .topLeading) { favoriteBadge }
                .overlay(alignment: .topTrailing) { selectionBadge }
                .overlay(alignment: .bottomTrailing) { videoBadge }

                VStack(spacing: 2) {
                    Text(file.name)
                        .font(.footnote)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)

                if hasTagPills {
                    tagPills
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: file.id) { await loadThumbnail() }
        .accessibilityLabel(file.name)
        .accessibilityHint(file.isDirectory ? "Dossier" : kind.label)
    }

    @ViewBuilder
    private var cardContent: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
        } else if kind.supportsThumbnail && isLoadingThumbnail {
            SkeletonView()
        } else {
            ZStack {
                cardTint.opacity(0.10)
                Image(systemName: kind.symbolName)
                    .font(.system(size: cardIconSize, weight: .regular))
                    .foregroundStyle(cardTint)
            }
        }
    }

    private var cardIconSize: CGFloat {
        let size = UIScreen.main.bounds.width / CGFloat(min(max(fileGridColumns, 2), 7))
        return max(24, size * 0.30)
    }

    @ViewBuilder
    private var favoriteBadge: some View {
        if showsFavoriteBadge, file.isFavorite == true {
            Image(systemName: "star.fill")
                .font(.caption2)
                .foregroundStyle(.yellow)
                .padding(5)
                .background(.ultraThinMaterial, in: Circle())
                .padding(6)
        }
    }

    @ViewBuilder
    private var selectionBadge: some View {
        if isSelectionMode {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(isSelected ? Color.accentColor : .white)
                .background(Circle().fill(isSelected ? .white : .black.opacity(0.25)))
                .padding(6)
        }
    }

    @ViewBuilder
    private var videoBadge: some View {
        if file.isVideo {
            Image(systemName: "play.fill")
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(5)
                .background(.black.opacity(0.45), in: Circle())
                .padding(6)
        }
    }

    @ViewBuilder
    private var tagPills: some View {
        let tags = Array((file.categories ?? []).prefix(4))
        if !tags.isEmpty {
            HStack(spacing: 3) {
                ForEach(tags, id: \.categoryId) { tag in
                    Circle()
                        .fill(CategoryPalette.color(for: tag.categoryId))
                        .frame(width: 7, height: 7)
                }
            }
        }
    }

    private var hasTagPills: Bool {
        !(file.categories ?? []).isEmpty
    }

    private var subtitle: String {
        if file.isDirectory { return kind.label }
        if showFileSizes { return ByteFormatter.string(file.size) }
        return kind.label
    }

    private func loadThumbnail() async {
        guard kind.supportsThumbnail, !file.isDirectory else { return }
        if let cached = ThumbnailProvider.cachedMemoryThumbnail(driveId: driveId, fileId: file.id) {
            thumbnail = cached
            return
        }
        isLoadingThumbnail = true
        let image = await ThumbnailProvider.shared.thumbnail(driveId: driveId, fileId: file.id,
                                                             isTrashed: false)
        isLoadingThumbnail = false
        thumbnail = image
    }
}

/// Squelette de chargement animé.
struct SkeletonView: View {
    @State private var shimmer = false

    var body: some View {
        RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
            .fill(Color.primary.opacity(0.07))
            .overlay(
                LinearGradient(colors: [.clear, .white.opacity(0.25), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .offset(x: shimmer ? 200 : -200)
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    shimmer = true
                }
            }
    }
}

/// Palette de couleurs des tags/dossiers.
enum CategoryPalette {
    static let colors: [String] = [
        "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#00C7BE",
        "#30B0C7", "#007AFF", "#5856D6", "#AF52DE", "#FF2D55",
        "#A2845E", "#8E8E93", "#4285F5", "#0F9D58", "#DB4437",
        "#F4B400", "#AB47BC", "#26A69A"
    ]

    private static let fallback = Color(red: 0.50, green: 0.53, blue: 0.58)

    static func color(for categoryId: Int) -> Color {
        let index = abs(categoryId) % colors.count
        return Color(hex: colors[index]) ?? fallback
    }
}
