import Combine
import SwiftUI

/// Vue racine : verrouillage, onboarding, bootstrap, ou app principale.
struct RootView: View {
    let session: SessionStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var isUnlocked = false
    @State private var hasGoneBackground = false

    var body: some View {
        Group {
            if AppLockStore.isConfigured && !isUnlocked {
                AppLockView(isConfigured: true) { isUnlocked = true }
            } else {
                sessionContent
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .apiUnauthorized)) { notification in
            guard let fingerprint = notification.object as? String else { return }
            session.handleUnauthorized(credentialFingerprint: fingerprint)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                if AppLockStore.isConfigured { isUnlocked = false }
                hasGoneBackground = true
            }
        }
    }

    @ViewBuilder
    private var sessionContent: some View {
        switch session.phase {
        case .signedOut:
            TokenSetupView(session: session)
        case .bootstrapping:
            BootSplash()
        case let .error(message):
            BootstrapErrorView(message: message) {
                Task { await session.bootstrap() }
            }
        case .signedIn:
            if let drive = session.selectedDrive {
                MainTabView(session: session, drive: drive)
                    .id(drive.id)
            } else {
                BootSplash()
            }
        }
    }
}

struct BootSplash: View {
    var body: some View {
        VStack(spacing: 18) {
            AppMark(size: 96)
            Text("Orvian")
                .font(.largeTitle.bold())
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

struct BootstrapErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            AppMark(size: 80)
            Text("Connexion impossible")
                .font(.title3.bold())
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Réessayer", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
