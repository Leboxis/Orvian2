import SwiftUI
import UIKit

/// Onglets de la barre flottante (gauche → droite).
enum AppTab: String, CaseIterable, Identifiable {
    case settings, tags, home, favorites, profile
    var id: String { rawValue }

    var title: String {
        switch self {
        case .settings: return "Réglages"
        case .tags: return "Tag"
        case .home: return "Accueil"
        case .favorites: return "Favoris"
        case .profile: return "Profil"
        }
    }

    var icon: String {
        switch self {
        case .settings: return "gearshape.fill"
        case .tags: return "tag.fill"
        case .home: return "house.fill"
        case .favorites: return "star.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }
}

/// Barre d'onglets flottante translucide, design Apple.
struct FloatingTabBar: View {
    let selection: AppTab
    let onSelect: (AppTab) -> Void
    let onReselect: (AppTab) -> Void

    @AppStorage("hapticFeedbackEnabled") private var hapticFeedbackEnabled = true

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.tabBarRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.tabBarRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .padding(.horizontal, DS.gridMargin + 8)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = tab == selection
        return Button {
            if isSelected {
                onReselect(tab)
            } else {
                if hapticFeedbackEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                onSelect(tab)
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 19, weight: .semibold))
                    .symbolEffect(.bounce, value: isSelected)
                Text(tab.title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.25), value: isSelected)
        .accessibilityLabel(tab.title)
    }
}
