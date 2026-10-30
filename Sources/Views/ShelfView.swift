import SwiftUI
import UniformTypeIdentifiers

/// Odkladiště souborů: přetáhni soubor na notch, pak ho vytáhni jinam nebo pošli přes AirDrop.
struct ShelfView: View {
    @EnvironmentObject private var shelf: ShelfStore
    @EnvironmentObject private var settings: AppSettings
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(targeted ? 0.12 : 0.06))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        targeted ? settings.accent.color : Color.white.opacity(0.18),
                        style: StrokeStyle(lineWidth: 1.2, dash: shelf.items.isEmpty ? [5, 4] : [])
                    )
                if shelf.items.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.down.doc").font(.system(size: 22, weight: .light))
                        Text("Přetáhni sem soubory").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Color.white.opacity(0.5))
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(shelf.items) { item in tile(item) }
                        }
                        .padding(12)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .animation(.smooth(duration: 0.2), value: targeted)
            .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
                shelf.add(providers: providers)
                return true
            }

            if !shelf.items.isEmpty {
                VStack(spacing: 8) {
                    GlassContainer(spacing: 8) {
                        VStack(spacing: 8) {
                            GlassIconButton(symbol: "airplayaudio", size: 34) { shelf.airDrop(shelf.items) }
                                .help("Poslat vše přes AirDrop")
                            GlassIconButton(symbol: "trash", size: 34) { shelf.clear() }
                                .help("Vyprázdnit odkladiště")
                        }
                    }
                }
            }
        }
    }

    private func tile(_ item: ShelfItem) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable()
                    .frame(width: 48, height: 48)
                Button { shelf.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.8), Color.black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }
            Text(item.name)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.8))
                .lineLimit(1)
                .frame(width: 70)
        }
        .padding(.top, 6)
        .onDrag {
            NSItemProvider(contentsOf: item.url) ?? NSItemProvider(object: item.url as NSURL)
        }
    }
}
