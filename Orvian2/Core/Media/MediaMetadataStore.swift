import AVFoundation
import Foundation
import Observation
import UIKit

/// Métadonnées vidéo (durée, orientation, 4K) avec persistance disque.
@MainActor
@Observable
final class MediaMetadataStore {
    static let shared = MediaMetadataStore()

    private(set) var revision = 0
    private(set) var allInfo: [Int: Info] = [:]

    struct Info: Codable, Hashable {
        var duration: Double?
        var orientation: FileFilters.Orientation?
        var maximumDimension: Int?
        var is4KOrAbove: Bool
    }

    private var persisted: [String: Info] = [:]
    private var saveTask: Task<Void, Never>?

    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Orvian2/video-metadata.json")
    }

    private init() {
        load()
    }

    func info(for fileId: Int) -> Info? { allInfo[fileId] }

    /// Résout les métadonnées manquantes (séquentiel, sans blocage du MainActor).
    func resolveAll(driveId: Int, items: [DriveFile]) async {
        let missing = items.filter { ($0.isVideo || $0.isImage) && allInfo[$0.id] == nil }
        guard !missing.isEmpty else { return }
        var changed = false
        for file in missing {
            if Task.isCancelled { break }
            if let info = await resolve(driveId: driveId, file: file) {
                allInfo[file.id] = info
                changed = true
            }
        }
        if changed {
            revision += 1
            scheduleSave()
        }
    }

    private func resolve(driveId: Int, file: DriveFile) async -> Info? {
        let key = "\(driveId)-\(file.id)"
        if let cached = persisted[key] {
            return cached
        }
        guard file.isVideo else {
            if file.isImage,
               let (dimension, orientation) = await Self.imageDimensions(driveId: driveId, fileId: file.id) {
                let info = Info(duration: nil, orientation: orientation,
                                maximumDimension: dimension, is4KOrAbove: dimension >= 3840)
                persisted[key] = info
                return info
            }
            return nil
        }
        guard let url = try? await MediaURLCache.shared.url(driveId: driveId, fileId: file.id) else { return nil }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration),
              let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
        let durationSeconds = CMTimeGetSeconds(duration)
        let naturalSize = (try? await track.load(.naturalSize)) ?? .zero
        let transform = (try? await track.load(.preferredTransform)) ?? .identity
        let transformed = naturalSize.applying(transform)
        let width = abs(transformed.width)
        let height = abs(transformed.height)
        let maximumDimension = Int(max(width, height))
        let ratio = height == 0 ? 1 : width / height
        let orientation: FileFilters.Orientation
        if ratio < 1.15 && ratio > 0.87 { orientation = .square }
        else if width > height { orientation = .landscape }
        else { orientation = .portrait }
        let info = Info(duration: durationSeconds.isFinite ? durationSeconds : nil,
                        orientation: orientation,
                        maximumDimension: maximumDimension,
                        is4KOrAbove: maximumDimension >= 3840)
        persisted[key] = info
        return info
    }

    private static func imageDimensions(driveId: Int, fileId: Int) async -> (Int, FileFilters.Orientation)? {
        guard let image = await HiresImageStore.shared.image(driveId: driveId, fileId: fileId) else { return nil }
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        let ratio = height == 0 ? 1.0 : Double(width) / Double(height)
        let orientation: FileFilters.Orientation
        if ratio < 1.15 && ratio > 0.87 { orientation = .square }
        else if width > height { orientation = .landscape }
        else { orientation = .portrait }
        return (max(width, height), orientation)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: Info].self, from: data) else { return }
        if decoded.count > 3000 {
            persisted = Dictionary(uniqueKeysWithValues: decoded.suffix(3000))
        } else {
            persisted = decoded
        }
    }

    private func save() {
        let snapshot = persisted
        let url = fileURL
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
