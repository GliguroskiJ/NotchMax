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
                            Capsule()
                                .fill(settings.accent.color.opacity(0.3))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
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

/// Záložka Nástroje: focus časovač.
struct ToolsHubView: View {
    var body: some View {
        ToolsView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Záložka Systém: 8 ukazatelů.
struct SystemHubView: View {
    var body: some View {
        StatsView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
