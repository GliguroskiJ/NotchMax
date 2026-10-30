import SwiftUI

/// Malý přepínač podsekcí (kapsle) nad obsahem záložky.
struct PaneSwitcher<T: Hashable>: View {
    struct Item {
        let value: T
        let title: String
        let symbol: String
    }

    let items: [Item]
    @Binding var selection: T
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<items.count, id: \.self) { index in
                let item = items[index]
                let active = item.value == selection
                Button {
                    withAnimation(.smooth(duration: 0.25)) { selection = item.value }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.symbol).font(.system(size: 11, weight: .semibold))
                        Text(item.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    }
                    .foregroundStyle(active ? Color.white : Color.white.opacity(0.6))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background {
                        if active {
                            Capsule().fill(settings.accent.color.opacity(0.3))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .notchGlass(in: Capsule(), tint: Color.white.opacity(0.04))
    }
}

enum ToolsSection: Hashable { case timer, shortcuts, notes }
enum SystemSection: Hashable { case stats, weather }

/// Záložka Nástroje: časovač, Zkratky, poznámky.
struct ToolsHubView: View {
    @State private var section: ToolsSection = .timer

    var body: some View {
        VStack(alignment: .leading, spacing: NotchLayout.spacingS) {
            PaneSwitcher<ToolsSection>(items: [
                PaneSwitcher<ToolsSection>.Item(value: .timer, title: "Časovač", symbol: "timer"),
                PaneSwitcher<ToolsSection>.Item(value: .shortcuts, title: "Zkratky", symbol: "bolt.fill"),
                PaneSwitcher<ToolsSection>.Item(value: .notes, title: "Poznámky", symbol: "note.text")
            ], selection: $section)
            Group {
                switch section {
                case .timer: ToolsView()
                case .shortcuts: ShortcutsView()
                case .notes: NotesView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
    }
}

/// Záložka Systém: statistiky a počasí.
struct SystemHubView: View {
    @State private var section: SystemSection = .stats

    var body: some View {
        VStack(alignment: .leading, spacing: NotchLayout.spacingS) {
            PaneSwitcher<SystemSection>(items: [
                PaneSwitcher<SystemSection>.Item(value: .stats, title: "Statistiky", symbol: "gauge.with.dots.needle.67percent"),
                PaneSwitcher<SystemSection>.Item(value: .weather, title: "Počasí", symbol: "cloud.sun.fill")
            ], selection: $section)
            Group {
                switch section {
                case .stats: StatsView()
                case .weather: WeatherView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
    }
}
