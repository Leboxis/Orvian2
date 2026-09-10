import SwiftUI

/// Onglet Réglages : préférences persistantes, cache, sécurité, compte.
struct SettingsView: View {
    let session: SessionStore
    let drive: Drive

    @AppStorage("showFileSizes") private var showFileSizes = true
    @AppStorage("fileGridColumns") private var fileGridColumns = 3
    @AppStorage("tagGridColumns") private var tagGridColumns = 2
    @AppStorage("foldersFirstInTags") private var foldersFirstInTags = true
    @AppStorage("alwaysShowSearch") private var alwaysShowSearch = false
    @AppStorage("defaultFolderColor") private var defaultFolderColor = "#4285F5"
    @AppStorage("favoritesReselectScrollToTop") private var favoritesReselectScrollToTop = true
    @AppStorage("prefetchThumbnails") private var prefetchThumbnails = true
    @AppStorage("prefetchVideoURLs") private var prefetchVideoURLs = true
    @AppStorage("prefetchOnWiFiOnly") private var prefetchOnWiFiOnly = false
    @AppStorage("thumbnailCacheLimitMB") private var thumbnailCacheLimitMB = 250
    @AppStorage("hapticFeedbackEnabled") private var hapticFeedbackEnabled = true
    @AppStorage("networkPerfEnabled") private var networkPerfEnabled = true

    @State private var showDrivePicker = false
    @State private var showTokenChange = false
    @State private var lockFlow: AppLockSetupSheet.Flow?
    @State private var cacheSize: Int64 = 0
    @State private var showTrash = false

    var body: some View {
        NavigationStack {
            Form {
                driveSection
                displaySection
                tagsSection
                searchSection
                favoritesSection
                prefetchSection
                cacheSection
                hapticsSection
                perfSection
                securitySection
                accountSection
            }
            .navigationTitle("Réglages")
            .task { cacheSize = await ThumbnailProvider.shared.diskCacheSize() }
            .sheet(isPresented: $showDrivePicker) {
                DrivePickerSheet(session: session)
            }
            .sheet(item: $lockFlow) { flow in
                AppLockSetupSheet(flow: flow)
            }
            .sheet(isPresented: $showTrash) {
                NavigationStack { TrashView(drive: drive) }
            }
        }
    }

    private var driveSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(drive.name).font(.headline)
                    Text(ByteFormatter.usage(used: drive.usedSize, total: drive.size))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Changer") { showDrivePicker = true }
                    .font(.footnote.weight(.semibold))
            }
            if let used = drive.usedSize, let total = drive.size, total > 0 {
                ProgressView(value: Double(used), total: Double(total))
            }
        }
    }

    private var displaySection: some View {
        Section("Affichage") {
            Toggle("Afficher le poids des fichiers", isOn: $showFileSizes)
            Stepper("Cartes par ligne : \(fileGridColumns)", value: $fileGridColumns, in: 2...7)
            Picker("Couleur par défaut des dossiers", selection: $defaultFolderColor) {
                ForEach(CategoryPalette.colors, id: \.self) { hex in
                    HStack {
                        Circle().fill(Color(hex: hex) ?? .gray).frame(width: 14, height: 14)
                        Text(hex)
                    }.tag(hex)
                }
            }
        }
    }

    private var tagsSection: some View {
        Section("Tags") {
            Picker("Colonnes des tags", selection: $tagGridColumns) {
                Text("2").tag(2)
                Text("3").tag(3)
            }
            .pickerStyle(.segmented)
            Toggle("Dossiers en premier dans les tags", isOn: $foldersFirstInTags)
        }
    }

    private var searchSection: some View {
        Section("Recherche") {
            Toggle("Recherche toujours visible", isOn: $alwaysShowSearch)
        }
    }

    private var favoritesSection: some View {
        Section("Favoris") {
            Toggle("Revenir en haut dans les favoris", isOn: $favoritesReselectScrollToTop)
        }
    }

    private var prefetchSection: some View {
        Section("Préchargement") {
            Toggle("Précharger les miniatures", isOn: $prefetchThumbnails)
            Toggle("Précharger les vidéos", isOn: $prefetchVideoURLs)
            Toggle("Précharger seulement en Wi-Fi", isOn: $prefetchOnWiFiOnly)
                .onChange(of: prefetchOnWiFiOnly) { _, _ in }
        }
    }

    private var cacheSection: some View {
        Section("Cache des miniatures") {
            Picker("Limite", selection: $thumbnailCacheLimitMB) {
                Text("250 Mo").tag(250)
                Text("500 Mo").tag(500)
                Text("1024 Mo").tag(1024)
                Text("Illimité").tag(0)
            }
            .onChange(of: thumbnailCacheLimitMB) { _, _ in
                Task { await ThumbnailProvider.shared.enforceDiskLimit() }
            }
            HStack {
                Text("Taille actuelle")
                Spacer()
                Text(ByteFormatter.format(cacheSize)).foregroundStyle(.secondary)
            }
            Button("Vider le cache", role: .destructive) {
                Task {
                    await ThumbnailProvider.shared.purgeDiskCache()
                    cacheSize = await ThumbnailProvider.shared.diskCacheSize()
                }
            }
        }
    }

    private var hapticsSection: some View {
        Section("Retours") {
            Toggle("Retours haptiques", isOn: $hapticFeedbackEnabled)
        }
    }

    private var perfSection: some View {
        Section("Diagnostic") {
            Toggle("Suivi des requêtes réseau", isOn: $networkPerfEnabled)
            NavigationLink("Statistiques réseau") { PerfView() }
        }
    }

    private var securitySection: some View {
        Section("Sécurité") {
            if AppLockStore.isConfigured {
                Button("Modifier le code") { lockFlow = .change }
                Button("Désactiver le code", role: .destructive) { lockFlow = .disable }
            } else {
                Button("Activer un code") { lockFlow = .activate }
            }
        }
    }

    private var accountSection: some View {
        Section("Compte") {
            Button("Changer de token") { showTokenChange = true }
            Button("Corbeille") { showTrash = true }
            Button("Se déconnecter", role: .destructive) { session.signOut() }
        }
        .sheet(isPresented: $showTokenChange) {
            TokenChangeSheet(session: session)
        }
    }
}

/// Sélecteur de drive.
struct DrivePickerSheet: View {
    let session: SessionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(session.drives) { drive in
                Button {
                    Task {
                        await session.selectDrive(drive)
                        dismiss()
                    }
                } label: {
                    HStack {
                        Image(systemName: "externaldrive.fill").foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading) {
                            Text(drive.name).foregroundStyle(.primary)
                            Text(ByteFormatter.usage(used: drive.usedSize, total: drive.size))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if drive.id == session.selectedDrive?.id {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            .navigationTitle("Choisir un drive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}

/// Changement de token.
struct TokenChangeSheet: View {
    let session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Nouveau token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Le token est stocké dans le Keychain (ou UserDefaults en repli).")
                }
            }
            .navigationTitle("Changer de token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Se connecter") {
                        Task {
                            await session.signIn(token: token)
                            dismiss()
                        }
                    }
                    .disabled(token.trimmingCharacters(in: .whitespaces).count < 20)
                }
            }
        }
    }
}
