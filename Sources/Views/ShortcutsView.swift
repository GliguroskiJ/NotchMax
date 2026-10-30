import SwiftUI

/// Zkratky: mřížka dlaždic pro spuštění Apple Shortcuts.
struct ShortcutsView: View {
    @ObservedObject private var store = ShortcutsStore.shared

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 120), spacing: NotchLayout.spacingS)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: NotchLayout.spacingS) {
            header
            if store.shortcuts.isEmpty {
                EmptyState(symbol: "bolt.slash",
                           title: "Žádné zkratky",
                           message: "Vytvoř je v aplikaci Zkratky")
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(columns: columns, spacing: NotchLayout.spacingS) {
                        ForEach(store.orderedShortcuts, id: \.self) { name in
                            ShortcutTile(
                                name: name,
                                isRunning: store.runningName == name,
                                isPinned: store.isPinned(name),
                                onRun: { store.run(name) },
                                onTogglePin: { store.togglePin(name) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.smooth(duration: 0.2), value: store.lastError)
        .onAppear { store.reload() }
    }

    private var header: some View {
        HStack(spacing: NotchLayout.spacingS) {
            CardLabel(symbol: "bolt.fill", title: "Zkratky")
            if let error = store.lastError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            GlassPill(title: "Obnovit", symbol: "arrow.clockwise") { store.reload() }
        }
    }
}

private struct ShortcutTile: View {
    let name: String
    let isRunning: Bool
    let isPinned: Bool
    let onRun: () -> Void
    let onTogglePin: () -> Void

    var body: some View {
        Button(action: onRun) {
            HStack(spacing: 6) {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 14, height: 14)
                }
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .notchGlass(in: Capsule(), tint: Color.white.opacity(0.04), interactive: true)
        .hoverScale(1.03)
        .contextMenu {
            Button(isPinned ? "Odepnout" : "Připnout", action: onTogglePin)
        }
    }
}
