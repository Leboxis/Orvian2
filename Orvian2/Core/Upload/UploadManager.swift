import Foundation
import Observation

/// Gestionnaire des uploads (photos + documents), concurrence bornée.
@MainActor
@Observable
final class UploadManager {
    static let shared = UploadManager()

    enum UploadStatus: Equatable {
        case queued
        case inProgress(progress: Double)
        case completed
        case failed(message: String)

        var isActive: Bool {
            switch self {
            case .queued, .inProgress: return true
            default: return false
            }
        }
    }

    struct UploadTaskItem: Identifiable, Equatable {
        let id: UUID
        var fileName: String
        var totalBytes: Int64
        var status: UploadStatus
        let date: Date
    }

    struct UploadPayload: Sendable {
        let fileURL: URL
        let fileName: String
        let totalBytes: Int64
        let isTemporary: Bool
    }

    private(set) var tasks: [UploadTaskItem] = []
    private(set) var isPillVisible = false

    static let maxConcurrentUploads = 4

    private let service = KDriveService()
    private var running = 0
    private var queue: [QueuedUpload] = []
    private var hideTask: Task<Void, Never>?

    private struct QueuedUpload {
        let id: UUID
        let driveId: Int
        let directoryId: Int
        let payload: UploadPayload
        let onDone: (@MainActor (Result<Void, Error>) -> Void)?
    }

    var activeTasksCount: Int { tasks.filter { $0.status.isActive }.count }
    var completedTasksCount: Int { tasks.filter { $0.status == .completed }.count }
    var hasFailures: Bool { tasks.contains { if case .failed = $0.status { return true } else { return false } } }

    var overallProgress: Double {
        guard !tasks.isEmpty else { return 0 }
        let total = tasks.reduce(0.0) { partial, task in
            switch task.status {
            case .completed: return partial + 1
            case let .inProgress(progress): return partial + progress
            default: return partial
            }
        }
        return total / Double(tasks.count)
    }

    // MARK: Enqueue

    func enqueuePhotos(driveId: Int, directoryId: Int, items: [UploadPayload],
                       onDone: (@MainActor (Result<Void, Error>) -> Void)? = nil) {
        enqueue(driveId: driveId, directoryId: directoryId, payloads: items, onDone: onDone)
    }

    func enqueueDocuments(driveId: Int, directoryId: Int, payloads: [UploadPayload],
                          onDone: (@MainActor (Result<Void, Error>) -> Void)? = nil) {
        enqueue(driveId: driveId, directoryId: directoryId, payloads: payloads, onDone: onDone)
    }

    private func enqueue(driveId: Int, directoryId: Int, payloads: [UploadPayload],
                         onDone: (@MainActor (Result<Void, Error>) -> Void)?) {
        guard !payloads.isEmpty else { return }
        for payload in payloads {
            let id = UUID()
            tasks.append(UploadTaskItem(id: id, fileName: payload.fileName,
                                        totalBytes: payload.totalBytes, status: .queued, date: Date()))
            queue.append(QueuedUpload(id: id, driveId: driveId, directoryId: directoryId,
                                      payload: payload, onDone: onDone))
        }
        showPill()
        pump()
    }

    func cancelAllAndClear() {
        queue.removeAll()
        tasks.removeAll()
        hidePill()
    }

    func clearCompleted() {
        tasks.removeAll { $0.status == .completed }
    }

    // MARK: Exécution

    private func pump() {
        while running < Self.maxConcurrentUploads, !queue.isEmpty {
            let upload = queue.removeFirst()
            running += 1
            Task { await self.perform(upload) }
        }
    }

    private func perform(_ upload: QueuedUpload) async {
        update(upload.id, status: .inProgress(progress: 0.15))
        let started = Date()
        let gate = ProgressGate()
        do {
            let lastModifiedAt = Int(started.timeIntervalSince1970)
            let size = upload.payload.totalBytes
            let id = upload.id
            try await service.uploadFile(
                driveId: upload.driveId,
                directoryId: upload.directoryId,
                fileURL: upload.payload.fileURL,
                fileName: upload.payload.fileName,
                totalSize: size,
                lastModifiedAt: upload.payload.isTemporary ? lastModifiedAt : nil,
                progress: { fraction in
                    let scaled = 0.2 + fraction * 0.8
                    guard gate.shouldReport(scaled) else { return }
                    Task { @MainActor [weak self] in
                        self?.update(id, status: .inProgress(progress: scaled))
                    }
                })
            update(upload.id, status: .completed)
            upload.onDone?(.success(()))
            await handleUploadSuccess(upload)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            update(upload.id, status: .failed(message: message))
            upload.onDone?(.failure(error))
        }
        running = max(0, running - 1)
        cleanupTemporaryFile(upload.payload)
        pump()
        scheduleHideIfIdle()
    }

    private func handleUploadSuccess(_ upload: QueuedUpload) async {
        FileGridMutationCenter.shared.publish(.uploaded(driveId: upload.driveId))
    }

    private func cleanupTemporaryFile(_ payload: UploadPayload) {
        guard payload.isTemporary else { return }
        try? FileManager.default.removeItem(at: payload.fileURL)
    }

    private func update(_ id: UUID, status: UploadStatus) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].status = status
    }

    // MARK: Pill

    private func showPill() {
        hideTask?.cancel()
        isPillVisible = true
    }

    private func hidePill() {
        hideTask?.cancel()
        isPillVisible = false
    }

    private func scheduleHideIfIdle() {
        guard activeTasksCount == 0 else { return }
        if hasFailures { return }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.isPillVisible = false
        }
    }
}
