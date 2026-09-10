import Foundation

/// Télécharge et décode les GIF (dédup).
actor GIFImageStore {
    typealias GIFImage = DecodedGIF

    static let shared = GIFImageStore()

    private var inFlight: [Int: Task<DecodedGIF?, Never>] = [:]

    func gif(driveId: Int, fileId: Int) async -> DecodedGIF? {
        if let task = inFlight[fileId] { return await task.value }
        let task = Task<DecodedGIF?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.download(driveId: driveId, fileId: fileId)
        }
        inFlight[fileId] = task
        let result = await task.value
        inFlight[fileId] = nil
        return result
    }

    private func download(driveId: Int, fileId: Int) async -> DecodedGIF? {
        do {
            let url = try await MediaURLCache.shared.url(driveId: driveId, fileId: fileId)
            let (localURL, _) = try await URLSession.shared.download(from: url)
            return await Task.detached(priority: .userInitiated) {
                GIFDecoder.decode(fromFile: localURL)
            }.value
        } catch {
            return nil
        }
    }

    nonisolated static func decode(fromFile url: URL) -> DecodedGIF? {
        GIFDecoder.decode(fromFile: url)
    }
}
