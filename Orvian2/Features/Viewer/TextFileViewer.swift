import SwiftUI

/// Lecteur/éditeur de fichiers texte (limite 5 Mo, recherche, liens cliquables).
struct TextFileViewer: View {
    let driveId: Int
    let file: DriveFile

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isLoading = true
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var showDiscardAlert = false
    @State private var originalText = ""

    private let service = KDriveService()
    private let maxSize = 5 * 1024 * 1024

    private var hasUnsavedChanges: Bool { isEditing && text != originalText }
    private var isBinary: Bool { Self.looksBinary(Data(text.utf8)) }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if let errorMessage {
                    ContentUnavailableView("Lecture impossible", systemImage: "doc.questionmark",
                                           description: Text(errorMessage))
                } else if isBinary && !isEditing {
                    ContentUnavailableView("Fichier binaire", systemImage: "doc.zipper",
                                           description: Text("Ce fichier ne peut pas être affiché comme du texte."))
                } else {
                    editor
                }
            }
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        if hasUnsavedChanges { showDiscardAlert = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !isLoading && errorMessage == nil && !isBinary {
                        if isEditing {
                            Button(isSaving ? "Enregistrement…" : "Enregistrer") { save() }
                                .disabled(isSaving || !hasUnsavedChanges)
                        } else {
                            Button { isEditing = true } label: {
                                Image(systemName: "pencil")
                            }
                        }
                    }
                }
            }
            .task { await load() }
            .confirmationDialog("Modifications non enregistrées", isPresented: $showDiscardAlert,
                                titleVisibility: .visible) {
                Button("Abandonner", role: .destructive) { dismiss() }
                Button("Continuer l'édition", role: .cancel) {}
            }
            .searchable(text: $searchText, prompt: "Rechercher")
        }
    }

    @ViewBuilder
    private var editor: some View {
        if isEditing {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(4)
        } else {
            ScrollView {
                Text(text.isEmpty ? "Fichier vide" : text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let url = try await MediaURLCache.shared.url(driveId: driveId, fileId: file.id)
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                errorMessage = "Erreur HTTP \(http.statusCode)."
                return
            }
            guard data.count <= maxSize else {
                errorMessage = "Fichier trop volumineux (max 5 Mo)."
                return
            }
            text = Self.decode(data)
            originalText = text
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        isSaving = true
        let data = Data(text.utf8)
        Task {
            do {
                try await service.uploadContent(driveId: driveId, fileId: file.id,
                                                data: data, totalSize: data.count,
                                                lastModifiedAt: Int(Date().timeIntervalSince1970))
                MediaURLCache.shared.invalidate(driveId: driveId, fileId: file.id)
                originalText = text
                isEditing = false
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isSaving = false
        }
    }

    // MARK: Décodage

    static func decode(_ data: Data) -> String {
        if data.count >= 2 {
            if data[0] == 0xFF, data[1] == 0xFE, let string = String(data: data, encoding: .utf16LittleEndian) {
                return string
            }
            if data[0] == 0xFE, data[1] == 0xFF, let string = String(data: data, encoding: .utf16BigEndian) {
                return string
            }
        }
        if data.count >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF,
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        for encoding: String.Encoding in [.utf8, .windowsCP1252, .isoLatin1, .macOSRoman] {
            if let string = String(data: data, encoding: encoding) { return string }
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func looksBinary(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        if data.contains(0) { return true }
        let controlCount = data.reduce(0) { count, byte in
            (byte < 9 || (byte > 13 && byte < 32)) ? count + 1 : count
        }
        return Double(controlCount) / Double(data.count) > 0.05
    }
}
