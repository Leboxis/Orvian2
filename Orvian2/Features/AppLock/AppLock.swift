import LocalAuthentication
import SwiftUI
import UIKit

// MARK: - Haptics

enum AppLockHaptics {
    static func success() { impact(.light) }
    static func failure() { impact(.heavy) }
    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard UserDefaults.standard.object(forKey: "hapticFeedbackEnabled") as? Bool ?? true else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - Biométrie

enum BiometricAuthenticator {
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    static var biometryLabel: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "Biométrie"
        }
    }
}

// MARK: - Effet de secousse

struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 9
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: travel * sin(animatableData * .pi * shakesPerUnit * 2), y: 0))
    }
}

// MARK: - Composants de code

struct CodeDots: View {
    let count: Int
    let filled: Int

    var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index < filled ? Color.primary : Color.primary.opacity(0.15))
                    .frame(width: 18, height: 18)
                    .scaleEffect(index < filled ? 1.12 : 1)
                    .animation(.snappy(duration: 0.18), value: filled)
            }
        }
        .accessibilityLabel("\(filled) chiffre(s) saisi(s)")
    }
}

struct CodeKeypad: View {
    let onDigit: (Int) -> Void
    let onDelete: () -> Void

    private let rows: [[KeypadKey]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.empty, .digit(0), .delete]
    ]

    enum KeypadKey: Hashable {
        case digit(Int)
        case delete
        case empty
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<rows.count, id: \.self) { rowIndex in
                HStack(spacing: 18) {
                    ForEach(rows[rowIndex], id: \.self) { key in
                        keyView(key)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func keyView(_ key: KeypadKey) -> some View {
        switch key {
        case let .digit(value):
            Button {
                AppLockHaptics.success()
                onDigit(value)
            } label: {
                Text("\(value)")
                    .font(.title2.weight(.medium))
                    .frame(width: 76, height: 64)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(KeypadButtonStyle())
        case .delete:
            Button {
                onDelete()
            } label: {
                Image(systemName: "delete.left")
                    .font(.title2)
                    .frame(width: 76, height: 64)
            }
            .buttonStyle(KeypadButtonStyle())
        case .empty:
            Color.clear.frame(width: 76, height: 64)
        }
    }
}

struct KeypadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Vue de verrouillage

struct AppLockView: View {
    let isConfigured: Bool
    let onUnlock: () -> Void

    @State private var code = ""
    @State private var shakes: CGFloat = 0
    @State private var errorText: String?
    @State private var didAttemptBiometrics = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Button {
                Task { await attemptBiometrics() }
            } label: {
                AppMark(size: 90)
            }
            .buttonStyle(.plain)

            VStack(spacing: 6) {
                Text("Orvian verrouillé")
                    .font(.title3.bold())
                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(.red)
                } else {
                    Text("Saisissez votre code")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            CodeDots(count: 4, filled: code.count)
                .modifier(ShakeEffect(animatableData: shakes))

            CodeKeypad(onDigit: append, onDelete: delete)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .task {
            if !didAttemptBiometrics {
                didAttemptBiometrics = true
                await attemptBiometrics()
            }
        }
    }

    private func append(_ digit: Int) {
        guard code.count < 4 else { return }
        code.append("\(digit)")
        if code.count == 4 { verify() }
    }

    private func delete() {
        guard !code.isEmpty else { return }
        code.removeLast()
    }

    private func verify() {
        if AppLockStore.verify(code) {
            AppLockHaptics.success()
            onUnlock()
        } else {
            AppLockHaptics.failure()
            errorText = "Code incorrect"
            withAnimation(.easeInOut(duration: 0.5)) { shakes += 1 }
            Task {
                try? await Task.sleep(nanoseconds: 850_000_000)
                code = ""
                errorText = nil
            }
        }
    }

    private func attemptBiometrics() async {
        guard isConfigured else { return }
        if await BiometricAuthenticator.authenticate(reason: "Déverrouiller Orvian") {
            onUnlock()
        }
    }
}

// MARK: - Configuration du code

struct AppLockSetupSheet: View {
    enum Flow: String, Identifiable {
        case activate, change, disable
        var id: String { rawValue }
    }

    enum Stage {
        case verifyCurrent, enterNew, confirmNew
    }

    let flow: Flow
    let onFinished: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var stage: Stage
    @State private var code = ""
    @State private var firstEntry = ""
    @State private var shakes: CGFloat = 0
    @State private var message: String?

    init(flow: Flow, onFinished: (() -> Void)? = nil) {
        self.flow = flow
        self.onFinished = onFinished
        _stage = State(initialValue: flow == .activate ? .enterNew : .verifyCurrent)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if let message {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }

                CodeDots(count: 4, filled: code.count)
                    .modifier(ShakeEffect(animatableData: shakes))

                CodeKeypad(onDigit: append, onDelete: delete)
                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .interactiveDismissDisabled(!code.isEmpty)
        }
    }

    private var navTitle: String {
        switch flow {
        case .activate: return "Activer le code"
        case .change: return "Modifier le code"
        case .disable: return "Désactiver le code"
        }
    }

    private var title: String {
        switch stage {
        case .verifyCurrent: return "Saisissez votre code actuel"
        case .enterNew: return "Choisissez un code à 4 chiffres"
        case .confirmNew: return "Confirmez votre nouveau code"
        }
    }

    private func append(_ digit: Int) {
        guard code.count < 4 else { return }
        code.append("\(digit)")
        if code.count == 4 { advance() }
    }

    private func delete() {
        guard !code.isEmpty else { return }
        code.removeLast()
    }

    private func advance() {
        switch stage {
        case .verifyCurrent:
            if AppLockStore.verify(code) {
                reset(withDelay: 0.2) { stage = flow == .disable ? .verifyCurrent : .enterNew }
                if flow == .disable {
                    AppLockStore.clear()
                    finish()
                }
            } else {
                fail(message: "Code incorrect")
            }
        case .enterNew:
            firstEntry = code
            reset(withDelay: 0.2) { stage = .confirmNew }
        case .confirmNew:
            if code == firstEntry {
                AppLockStore.save(code)
                finish()
            } else {
                fail(message: "Les codes ne correspondent pas")
                firstEntry = ""
                Task {
                    try? await Task.sleep(nanoseconds: 850_000_000)
                    stage = .enterNew
                }
            }
        }
    }

    private func fail(message: String) {
        self.message = message
        AppLockHaptics.failure()
        withAnimation(.easeInOut(duration: 0.5)) { shakes += 1 }
        Task {
            try? await Task.sleep(nanoseconds: 850_000_000)
            code = ""
            self.message = nil
        }
    }

    private func reset(withDelay delay: TimeInterval, next: @escaping () -> Void) {
        AppLockHaptics.success()
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            code = ""
            next()
        }
    }

    private func finish() {
        onFinished?()
        dismiss()
    }
}
