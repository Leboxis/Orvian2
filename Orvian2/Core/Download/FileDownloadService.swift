import Combine
import UIKit

/// Télécharge un fichier puis ouvre la feuille de partage.
@MainActor
final class FileDownloadService: ObservableObject {
    static let shared = FileDownloadService()

    @Published var isDownloading = false
    @Published var progress: Double = 0
    @Published var downloadingFileName: String?
    @Published var errorMessage: String?

    private var session: URLSession?
    private var currentTask: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<URL, Error>?

    func downloadAndShare(driveId: Int, file: DriveFile) async {
        guard !file.isDirectory else { return }
        isDownloading = true
        progress = 0
        downloadingFileName = file.name
        defer {
            isDownloading = false
            downloadingFileName = nil
            session?.finishTasksAndInvalidate()
            session = nil
            currentTask = nil
        }
        do {
            let url = try await MediaURLCache.shared.url(driveId: driveId, fileId: file.id)
            let localURL = try await download(from: url)
            let safeName = Self.safeFileName(file.name)
            let directory = Self.downloadDirectory()
            let destination = directory.appendingPathComponent(safeName)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: localURL, to: destination)
            presentShareSheet(url: destination)
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch is CancellationError {
            // Annulation demandée par l'utilisateur.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelDownload() {
        currentTask?.cancel()
        isDownloading = false
    }

    private func download(from url: URL) async throws -> URL {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
        let delegate = DownloadDelegate(
            onProgress: { [weak self] fraction in
                Task { @MainActor in self?.progress = fraction }
            },
            onFinish: { [weak self] result in
                Task { @MainActor in
                    guard let self, let continuation = self.continuation else { return }
                    self.continuation = nil
                    continuation.resume(with: result)
                }
            })
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        self.session = session
        let task = session.downloadTask(with: request)
        currentTask = task
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            task.resume()
        }
    }

    private func presentShareSheet(url: URL) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        var controller = root
        while let presented = controller.presentedViewController { controller = presented }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        controller.present(activity, animated: true)
    }

    static func downloadDirectory() -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrvianDownloads", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Nom de fichier sûr (pas de séparateurs, limite en octets).
    static func safeFileName(_ name: String) -> String {
        var sanitized = name
        for character in ["/", "\\", ":"] {
            sanitized = sanitized.replacingOccurrences(of: character, with: "_")
        }
        let ext = (sanitized as NSString).pathExtension
        var base = (sanitized as NSString).deletingPathExtension
        if base.utf8.count > 200 {
            base = String(base.prefix(200))
        }
        let safeExtension = ext.utf8.count > 24 ? String(ext.prefix(24)) : ext
        return safeExtension.isEmpty ? base : "\(base).\(safeExtension)"
    }
}

/// Delegate de téléchargement : progression + achèvement.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private let onFinish: @Sendable (Result<URL, Error>) -> Void
    private var lastReported = 0.0

    init(onProgress: @escaping @Sendable (Double) -> Void,
         onFinish: @escaping @Sendable (Result<URL, Error>) -> Void) {
        self.onProgress = onProgress
        self.onFinish = onFinish
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        if fraction - lastReported >= 0.01 || fraction >= 1 {
            lastReported = fraction
            onProgress(fraction)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("orvian-dl-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            onFinish(.success(destination))
        } catch {
            onFinish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { onFinish(.failure(error)) }
    }
}

extension UIWindowScene {
    var keyWindow: UIWindow? {
        windows.first { $0.isKeyWindow } ?? windows.first
    }
}
