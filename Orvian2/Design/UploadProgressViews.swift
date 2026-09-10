import SwiftUI

/// Pilule de progression des uploads.
struct UploadProgressPill: View {
    @State private var uploads = UploadManager.shared
    @State private var showSheet = false

    private var label: String {
        if uploads.hasFailures { return "Échec d'import" }
        if uploads.activeTasksCount > 0 {
            return "Import \(Int(uploads.overallProgress * 100)) %"
        }
        return "Terminé"
    }

    private var icon: String {
        if uploads.hasFailures { return "exclamationmark.triangle.fill" }
        if uploads.activeTasksCount > 0 { return "arrow.up.circle.fill" }
        return "checkmark.circle.fill"
    }

    var body: some View {
        Button { showSheet = true } label: {
            HStack(spacing: 10) {
                if uploads.activeTasksCount > 0 {
                    ProgressView(value: uploads.overallProgress)
                        .progressViewStyle(.circular)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: icon)
                        .foregroundStyle(uploads.hasFailures ? .red : .green)
                }
                Text(label).font(.footnote.weight(.medium))
                Image(systemName: "chevron.up").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            UploadProgressSheet()
        }
    }
}

/// Feuille détaillant les transferts.
struct UploadProgressSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var uploads = UploadManager.shared

    var body: some View {
        NavigationStack {
            List {
                if uploads.tasks.isEmpty {
                    Text("Aucun transfert").foregroundStyle(.secondary)
                } else {
                    ForEach(uploads.tasks) { task in
                        HStack(spacing: 12) {
                            statusIcon(task.status)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(task.fileName).font(.subheadline).lineLimit(1)
                                statusDetail(task)
                            }
                            Spacer()
                            Text(ByteFormatter.format(task.totalBytes))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Transferts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Effacer") { uploads.clearCompleted() }
                        .disabled(uploads.completedTasksCount == 0)
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: UploadManager.UploadStatus) -> some View {
        switch status {
        case .queued:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .inProgress:
            ProgressView().frame(width: 18, height: 18)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func statusDetail(_ task: UploadManager.UploadTaskItem) -> some View {
        switch task.status {
        case let .inProgress(progress):
            ProgressView(value: progress).frame(maxWidth: 180)
        case let .failed(message):
            Text(message).font(.caption2).foregroundStyle(.red).lineLimit(1)
        case .completed:
            Text("Terminé").font(.caption2).foregroundStyle(.secondary)
        case .queued:
            Text("En attente").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
