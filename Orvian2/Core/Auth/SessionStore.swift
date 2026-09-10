import Observation
import SwiftUI

/// État global de session : onboarding, bootstrap, drive sélectionné.
@MainActor
@Observable
final class SessionStore {
    enum Phase: Equatable {
        case signedOut
        case bootstrapping
        case signedIn
        case error(String)
    }

    private(set) var phase: Phase = .signedOut
    private(set) var drives: [Drive] = []
    private(set) var accountId: Int?
    private(set) var selectedDrive: Drive?
    private(set) var signedOutMessage: String?

    static let expiredSessionMessage = "Votre session a expiré. Reconnectez-vous avec un nouveau token."

    private let accountIdKey = "orvian2.account-id"
    private let driveIdKey = "orvian2.drive-id"
    private let service = KDriveService()

    init() {
        if let stored = UserDefaults.standard.object(forKey: accountIdKey) as? Int {
            accountId = stored
        }
    }

    func bootstrap() async {
        guard let token = TokenStore.current(), !token.isEmpty else {
            phase = .signedOut
            return
        }
        phase = .bootstrapping
        do {
            try await loadDrives(preferredDriveId: UserDefaults.standard.object(forKey: driveIdKey) as? Int)
            phase = .signedIn
        } catch let error as APIError where error.isUnauthorized {
            clearSession(message: Self.expiredSessionMessage)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    func signIn(token: String) async {
        DirectoryListStore.shared.clear()
        CategoryLibrary.shared.clear()
        _ = TokenStore.save(token)
        phase = .bootstrapping
        do {
            try await loadDrives(preferredDriveId: nil)
            phase = .signedIn
        } catch let error as APIError where error.isUnauthorized {
            TokenStore.clear()
            phase = .error("Token invalide ou expiré (401).")
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    func signOut() {
        clearSession(message: nil)
    }

    func handleUnauthorized(credentialFingerprint: String) {
        guard credentialFingerprint == TokenStore.credentialFingerprint() else { return }
        clearSession(message: Self.expiredSessionMessage)
    }

    func selectDrive(_ drive: Drive) async {
        selectedDrive = drive
        UserDefaults.standard.set(drive.id, forKey: driveIdKey)
        await reloadDrives()
    }

    func reloadDrives() async {
        do {
            try await loadDrives(preferredDriveId: selectedDrive?.id)
        } catch {
            // Conserve l'état courant en cas d'échec silencieux.
        }
    }

    private func loadDrives(preferredDriveId: Int?) async throws {
        let (accountId, drives) = try await service.discoverDrives()
        self.accountId = accountId
        self.drives = drives
        UserDefaults.standard.set(accountId, forKey: accountIdKey)

        let preferred = drives.first { $0.id == preferredDriveId } ?? drives.first
        guard let preferred else {
            throw APIError.http(status: 404, code: "no_drive", description: "Aucun drive disponible.")
        }
        selectedDrive = preferred
        UserDefaults.standard.set(preferred.id, forKey: driveIdKey)
    }

    private func clearSession(message: String?) {
        UploadManager.shared.cancelAllAndClear()
        DirectoryListStore.shared.clear()
        CategoryLibrary.shared.clear()
        TokenStore.clear()
        UserDefaults.standard.removeObject(forKey: accountIdKey)
        UserDefaults.standard.removeObject(forKey: driveIdKey)
        drives = []
        accountId = nil
        selectedDrive = nil
        signedOutMessage = message
        phase = .signedOut
    }
}
