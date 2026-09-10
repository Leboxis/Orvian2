import SwiftUI

/// Design system central : rayons, espacements et couleurs partagées.
enum DS {
    static let cardRadius: CGFloat = 18
    static let tabBarRadius: CGFloat = 28
    static let gridSpacing: CGFloat = 10
    static let gridMargin: CGFloat = 14
    static let searchBarInset: CGFloat = 52
    static let cardRadiusContinuous = RoundedCornerStyle.continuous
}

extension View {
    /// Carte arrondie continue avec fond matériau.
    func dsCard(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
    }
}

/// En-tête de section avec trait.
struct SectionHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }
}

/// État vide générique.
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var description: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let description { Text(description) }
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.top, 60)
    }
}

/// Monogramme de l'app (dégradé bleu → violet).
struct AppMark: View {
    var size: CGFloat = 88

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.23, green: 0.51, blue: 0.98),
                                              Color(red: 0.55, green: 0.32, blue: 0.93)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .fill(.white.opacity(0.22))
                .frame(width: size * 0.42)
                .offset(x: -size * 0.16, y: -size * 0.16)
            Circle()
                .fill(.white.opacity(0.16))
                .frame(width: size * 0.30)
                .offset(x: size * 0.18, y: size * 0.20)
            Triangle()
                .fill(.white.opacity(0.92))
                .frame(width: size * 0.30, height: size * 0.26)
                .offset(x: size * 0.02, y: -size * 0.02)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.18), radius: size * 0.12, y: size * 0.05)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
