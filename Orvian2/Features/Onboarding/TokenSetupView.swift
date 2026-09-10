import SwiftUI

/// Onboarding : saisie du token Infomaniak.
struct TokenSetupView: View {
    let session: SessionStore

    @State private var token = ""
    @State private var showHelp = false
    @State private var isConnecting = false

    private var isValid: Bool { token.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 60)
                AppMark(size: 100)

                VStack(spacing: 8) {
                    Text("Orvian")
                        .font(.largeTitle.bold())
                    Text("Votre kDrive, en toute simplicité")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 14) {
                    SecureField("Token API Infomaniak", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )

                    Button {
                        connect()
                    } label: {
                        HStack {
                            if isConnecting { ProgressView().tint(.white) }
                            Text(isConnecting ? "Connexion…" : "Se connecter")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!isValid || isConnecting)

                    Button("Où trouver mon token ?") { showHelp = true }
                        .font(.footnote)
                }

                Label("Le token est conservé dans le Keychain de l'iPhone.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let message = session.signedOutMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 24)
        }
        .background(
            LinearGradient(colors: [Color.accentColor.opacity(0.08), Color(.systemGroupedBackground)],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        )
        .sheet(isPresented: $showHelp) {
            TokenHelpSheet()
        }
    }

    private func connect() {
        isConnecting = true
        let value = token
        Task {
            await session.signIn(token: value)
            isConnecting = false
        }
    }
}

/// Aide : création du token.
struct TokenHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    step(number: 1, text: "Rendez-vous sur developer.infomaniak.com et connectez-vous.")
                    step(number: 2, text: "Créez un token d'accès avec les droits kDrive (lecture/écriture).")
                    step(number: 3, text: "Copiez le token généré, puis collez-le dans Orvian.")
                    Link("Ouvrir developer.infomaniak.com", destination: URL(string: "https://developer.infomaniak.com")!)
                        .font(.subheadline.weight(.semibold))
                }
                .padding()
            }
            .navigationTitle("Obtenir un token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func step(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.footnote.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.subheadline)
        }
    }
}
