import SwiftUI

/// Onglet Tag : gestion et navigation par catégories.
struct TagsView: View {
    let session: SessionStore
    let drive: Drive

    @Environment(ViewerRouter.self) private var router
    @State private var library = CategoryLibrary.shared
    @AppStorage("tagGridColumns") private var tagGridColumns = 2
    @AppStorage("foldersFirstInTags") private var foldersFirstInTags = true

    @State private var path = NavigationPath()
    @State private var showCreate = false
    @State private var editCategory: Category?
    @State private var deleteCategory: Category?

    private var categories: [Category] {
        let all = library.categories(for: drive.id)
        if let order = TagOrderStore.order(for: drive.id) {
            return all.sorted { lhs, rhs in
                let li = order.firstIndex(of: lhs.id) ?? Int.max
                let ri = order.firstIndex(of: rhs.id) ?? Int.max
                if li != ri { return li < ri }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
        return all
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if categories.isEmpty {
                    EmptyStateView(title: "Aucun tag", systemImage: "tag",
                                   description: "Créez votre premier tag pour organiser vos fichiers.",
                                   actionTitle: "Créer un tag") { showCreate = true }
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                             count: min(max(tagGridColumns, 2), 3)),
                              spacing: 12) {
                        ForEach(categories) { category in
                            TagGridCard(category: category, count: category.userUses ?? 0)
                                .onTapGesture { path.append(category) }
                                .contextMenu {
                                    Button { editCategory = category } label: {
                                        Label("Renommer", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) { deleteCategory = category } label: {
                                        Label("Supprimer", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(DS.gridMargin)
                }
            }
            .navigationTitle("Tags")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: Category.self) { category in
                CategoryFilesView(drive: drive, category: category,
                                  foldersFirst: foldersFirstInTags,
                                  open: { file, siblings in router.open(file, siblings: siblings) },
                                  push: { path.append($0) })
            }
            .navigationDestination(for: DriveFile.self) { folder in
                FileGridView(
                    viewModel: FileGridViewModel(source: .directory(folder.id), driveId: drive.id),
                    driveId: drive.id,
                    source: .directory(folder.id),
                    onOpenDirectory: { path.append($0) },
                    onOpenFile: { file, siblings in router.open(file, siblings: siblings) }
                )
                .navigationTitle(folder.name)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task { await library.ensureLoaded(driveId: drive.id) }
        .sheet(isPresented: $showCreate) {
            CreateTagSheet(driveId: drive.id)
        }
        .sheet(item: $editCategory) { category in
            CreateTagSheet(driveId: drive.id, editing: category)
        }
        .confirmationDialog("Supprimer ce tag ?", isPresented: Binding(
            get: { deleteCategory != nil },
            set: { if !$0 { deleteCategory = nil } }
        ), titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                if let category = deleteCategory {
                    Task {
                        try? await KDriveService().deleteCategory(driveId: drive.id, categoryId: category.id)
                        library.remove(categoryId: category.id, driveId: drive.id)
                    }
                }
                deleteCategory = nil
            }
            Button("Annuler", role: .cancel) { deleteCategory = nil }
        }
    }
}

/// Carte de tag.
struct TagGridCard: View {
    let category: Category
    let count: Int

    private var color: Color {
        Color(hex: category.color ?? "") ?? CategoryPalette.color(for: category.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "tag.fill")
                    .font(.title3)
                    .foregroundStyle(color)
                Spacer()
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(category.name)
                .font(.headline)
                .lineLimit(1)
            Text("fichier\(count > 1 ? "s" : "")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                .strokeBorder(color.opacity(0.25), lineWidth: 1)
        )
    }
}

/// Fichiers d'une catégorie.
struct CategoryFilesView: View {
    let drive: Drive
    let category: Category
    let foldersFirst: Bool
    let open: (DriveFile, [DriveFile]) -> Void
    let push: (DriveFile) -> Void

    @State private var viewModel: FileGridViewModel

    init(drive: Drive, category: Category, foldersFirst: Bool,
         open: @escaping (DriveFile, [DriveFile]) -> Void,
         push: @escaping (DriveFile) -> Void) {
        self.drive = drive
        self.category = category
        self.foldersFirst = foldersFirst
        self.open = open
        self.push = push
        _viewModel = State(initialValue: FileGridViewModel(source: .category(category.id), driveId: drive.id))
    }

    var body: some View {
        FileGridView(
            viewModel: viewModel,
            driveId: drive.id,
            source: .category(category.id),
            onOpenDirectory: { push($0) },
            onOpenFile: { file, siblings in open(file, siblings) }
        )
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Création / édition d'un tag.
struct CreateTagSheet: View {
    let driveId: Int
    var editing: Category?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedColor = CategoryPalette.colors.first ?? "#007AFF"
    @State private var customColor = Color.blue
    @State private var isSaving = false

    private let service = KDriveService()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom") {
                    TextField("Nom du tag", text: $name)
                }
                Section("Couleur") {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(CategoryPalette.colors, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex) ?? .gray)
                                .frame(height: 36)
                                .overlay {
                                    if hex == selectedColor {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { selectedColor = hex }
                        }
                    }
                    ColorPicker("Couleur personnalisée", selection: $customColor)
                        .onChange(of: customColor) { _, color in
                            if let hex = color.toHex() { selectedColor = hex }
                        }
                }
            }
            .navigationTitle(editing == nil ? "Nouveau tag" : "Modifier le tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear {
                if let editing {
                    name = editing.name
                    selectedColor = editing.color ?? selectedColor
                }
            }
        }
    }

    private func save() {
        isSaving = true
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            if let editing {
                if let updated = try? await service.updateCategory(driveId: driveId, categoryId: editing.id,
                                                                   name: trimmed, color: selectedColor) {
                    CategoryLibrary.shared.upsert(updated, driveId: driveId)
                }
            } else if let created = try? await service.createCategory(driveId: driveId, name: trimmed,
                                                                      color: selectedColor) {
                CategoryLibrary.shared.upsert(created, driveId: driveId)
            }
            isSaving = false
            dismiss()
        }
    }
}
