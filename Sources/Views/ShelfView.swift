import SwiftUI
import UniformTypeIdentifiers

/// Odkladiště souborů: přetáhni soubor na notch, pak ho vytáhni jinam nebo pošli přes AirDrop.
struct ShelfView: View {
    @EnvironmentObject private var shelf: ShelfStore
    @EnvironmentObject private var settings: AppSettings
    @State private var targeted = false

    private var dropShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: NotchLayout.cardRadius, style: .continuous)
    }

    var body: some View {
        HStack(spacing: NotchLayout.spacingM) {
            dropZone
            if !shelf.items.isEmpty {
                actions
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.smooth(duration: 0.3), value: shelf.items.isEmpty)
    }

    private var dropZone: some View {
        let isEmpty = shelf.items.isEmpty
        let border: Color = targeted ? settings.accent.color.opacity(0.9) : Color.white.opacity(isEmpty ? 0.2 : 0.09)
        let dash: [CGFloat] = isEmpty ? [6, 5] : []
        return ZStack {
            if isEmpty {
                EmptyState(symbol: targeted ? "arrow.down.circle.fill" : "arrow.down.doc",
                           title: "Přetáhni sem soubory",
                           message: "Odsud je pak přetáhneš jinam nebo pošleš přes AirDrop")
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: NotchLayout.spacingS) {
                        ForEach(shelf.items) { item in
                            ShelfTile(item: item) { shelf.remove(item) }
                        }
                    }
                    .padding(10)
                    .frame(maxHeight: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .notchGlass(in: dropShape, tint: targeted ? settings.accent.color.opacity(0.22) : Color.white.opacity(0.06))
        .background(dropShape.fill(Color.black.opacity(0.28)))
        .overlay(dropShape.strokeBorder(border, style: StrokeStyle(lineWidth: 1, dash: dash)))
        .animation(.smooth(duration: 0.2), value: targeted)
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            shelf.add(providers: providers)
            return true
        }
    }

    private var actions: some View {
        GlassContainer(spacing: NotchLayout.spacingS) {
            VStack(spacing: NotchLayout.spacingS) {
                GlassIconButton(symbol: "airplayaudio", size: 40) { shelf.airDrop(shelf.items) }
                    .help("Poslat vše přes AirDrop")
                GlassIconButton(symbol: "trash", size: 40) { shelf.clear() }
                    .help("Vyprázdnit odkladiště")
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct ShelfTile: View {
    let item: ShelfItem
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 44, height: 44)
            Text(item.name)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 70)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: NotchLayout.nestedRadius, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.11 : 0.07))
        )
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.85), Color.black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0.5)
            .padding(4)
        }
        .animation(.smooth(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        .onDrag {
            NSItemProvider(contentsOf: item.url) ?? NSItemProvider(object: item.url as NSURL)
        }
    }
}
