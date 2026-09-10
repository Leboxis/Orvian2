import SwiftUI

/// Détails d'un fichier + actions rapides.
struct FileDetailSheet: View {
    let file: DriveFile
    let driveId: Int
    let viewModel: FileGridViewModel
    let source: FileSource
    let onOpen: (DriveFile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var renameText = ""
    @State private var showRename = false

    private var isTrash: Bool {
        if case .trash = source { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: file.fileKind.symbolName)
                            .font(.system(size: 30))
                            .foregroundStyle(file.isDirectory ? folderTint : file.fileKind.tint)
                            .frame(width: 54, height: 54)
                            .background((file.isDirectory ? folderTint : file.fileKind.tint).opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.name)
                                .font(.headline)
                                .lineLimit(2)
                            Text(file.fileKind.label)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Informations") {
                    infoRow("Type", file.fileKind.label)
                    infoRow("Taille", file.isDirectory ? "—" : ByteFormatter.string(file.size))
                    if let path = file.path { infoRow("Emplacement", path) }
                    if let added = file.addedAt {
                        infoRow("Ajouté", Self.dateString(added))
                    }
                    if let modified = file.updatedAt ?? file.lastModifiedAt {
                        infoRow("Modifié", Self.dateString(modified))
                    }
                    infoRow("Favori", file.isFavorite == true ? "Oui" : "Non")
                }

                if !(file.categories ?? []).isEmpty {
                    Section("Tags") {
                        ForEach(file.categories ?? []) { category in
                            HStack(spacing: 10) {
                                Circle().fill(CategoryPalette.color(for: category.categoryId))
                                    .frame(width: 10, height: 10)
                                Text("Tag #\(category.categoryId)")
                            }
                        }
                    }
                }

                if !isTrash {
                    Section {
                        Button {
                            onOpen(file)
                            dismiss()
                        } label: {
                            Label("Ouvrir", systemImage: "arrow.up.forward.app")
                        }
                        if !file.isDirectory {
                            Button {
                                Task { await FileDownloadService.shared.downloadAndShare(driveId: driveId, file: file) }
                            } label: {
                                Label("Télécharger", systemImage: "arrow.down.circle")
                            }
                        }
                        Button { showRename = true } label: {
                            Label("Renommer", systemImage: "pencil")
                        }
                    }
                }
            }
            .navigationTitle("Détails")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .alert("Renommer", isPresented: $showRename) {
                TextField("Nom", text: $renameText)
                Button("Annuler", role: .cancel) {}
                Button("Renommer") {
                    Task { await viewModel.rename(file, to: renameText) }
                }
            }
            .onAppear { renameText = file.name }
        }
    }

    private var folderTint: Color {
        if let hex = file.color, let color = Color(hex: hex) { return color }
        return file.fileKind.tint
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    static func dateString(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// Édite les tags d'un fichier (toggle optimiste).
struct TagsEditorSheet: View {
    let file: DriveFile
    let driveId: Int
    let viewModel: FileGridViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var library = CategoryLibrary.shared
    @AppStorage("tagGridColumns") private var tagGridColumns = 2

    private var categories: [Category] { library.categories(for: driveId) }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: min(max(tagGridColumns, 2), 3))
    }

    var body: some View {
        NavigationStack {
            Group {
                if categories.isEmpty {
                    EmptyStateView(title: "Aucun tag", systemImage: "tag",
                                   description: "Créez des tags dans l'onglet Tag.")
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(categories) { category in
                                Button {
                                    Task { await viewModel.toggleCategory(file, categoryId: category.id) }
                                } label: {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color(hex: category.color ?? "") ?? CategoryPalette.color(for: category.id))
                                            .frame(width: 12, height: 12)
                                        Text(category.name)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                        Spacer()
                                        if isApplied(category.id) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                    .padding(12)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(DS.gridMargin)
                    }
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
            .task { await library.ensureLoaded(driveId: driveId) }
        }
    }

    private func isApplied(_ categoryId: Int) -> Bool {
        (viewModel.items.first { $0.id == file.id }?.categories ?? file.categories ?? [])
            .contains { $0.categoryId == categoryId }
    }
}

/// Palette de couleurs de dossier.
struct FolderColorPickerSheet: View {
    let file: DriveFile
    let viewModel: FileGridViewModel

    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultFolderColor") private var defaultFolderColor = "#4285F5"

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(CategoryPalette.colors, id: \.self) { hex in
                        Button {
                            Task { await viewModel.setColor(file, color: hex) }
                            dismiss()
                        } label: {
                            Circle()
                                .fill(Color(hex: hex) ?? .gray)
                                .frame(height: 44)
                                .overlay {
                                    if hex.caseInsensitiveCompare(file.color ?? "") == .orderedSame {
                                        Image(systemName: "checkmark")
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(DS.gridMargin)
            }
            .navigationTitle("Couleur du dossier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }
}
