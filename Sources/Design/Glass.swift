import SwiftUI

// MARK: - Liquid Glass s fallbackem
//
// macOS 26+: nativní `glassEffect`. Starší systémy: matný „sklíčkový“ materiál
// s odleskem a obrysem. Nativní větev se kompiluje jen s Xcode 26 (Swift 6.2+),
// jinak se použije fallback i na novém systému.

#if compiler(>=6.2)
@available(macOS 26.0, *)
fileprivate extension View {
    func nativeGlass<S: InsettableShape>(_ shape: S, tint: Color?, interactive: Bool) -> some View {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return self.glassEffect(glass, in: shape)
    }
}
#endif

struct FallbackGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(shape.fill(Color.white.opacity(reduceTransparency ? 0.2 : 0.11)))
            .background(shape.fill(tint ?? Color.clear))
            .overlay(
                shape.fill(
                    LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0)],
                                   startPoint: .top, endPoint: .center)
                )
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.08)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.75
                )
            )
            .clipShape(shape)
    }
}

extension View {
    /// Sklo pro malé ovládací prvky (ne pro velké plochy a ne pro celý notch).
    @ViewBuilder
    func notchGlass<S: InsettableShape>(in shape: S, tint: Color? = nil, interactive: Bool = false, enabled: Bool = true) -> some View {
        if !enabled {
            self
        } else {
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                self.nativeGlass(shape, tint: tint, interactive: interactive)
            } else {
                self.modifier(FallbackGlass(shape: shape, tint: tint))
            }
            #else
            self.modifier(FallbackGlass(shape: shape, tint: tint))
            #endif
        }
    }

    /// Karta z Liquid Glass (na macOS 26 nativní sklo, jinak fallback).
    func cardStyle() -> some View {
        glassCard(padding: NotchLayout.spacingL)
    }

    /// Karta s jednotným poloměrem (soustředným k tvaru panelu), tmavou podložkou pro kontrast
    /// a jemným světlým obrysem. `padding` je vnitřní odsazení obsahu.
    func glassCard(padding: CGFloat = NotchLayout.spacingL) -> some View {
        let shape = RoundedRectangle(cornerRadius: NotchLayout.cardRadius, style: .continuous)
        return self
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .notchGlass(in: shape, tint: Color.white.opacity(0.06))
            .background(shape.fill(Color.black.opacity(0.28)))
            .overlay(shape.strokeBorder(Color.white.opacity(0.09), lineWidth: 0.75))
    }

    /// Jemné zvětšení při najetí myší.
    func hoverScale(_ scale: CGFloat = 1.06) -> some View {
        modifier(HoverScale(scale: scale))
    }
}

struct HoverScale: ViewModifier {
    let scale: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? scale : 1)
            .animation(.smooth(duration: 0.16), value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Seskupí skleněné prvky (na macOS 26 se opticky slévají a morphují).
struct GlassContainer<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

struct GlassIconButton: View {
    let symbol: String
    var prominent = false
    var tint: Color?
    var size: CGFloat = 34
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .notchGlass(in: Circle(), tint: prominent ? (tint ?? Color.white.opacity(0.3)) : nil, interactive: true)
        .hoverScale()
    }
}

struct GlassPill: View {
    let title: String
    var symbol: String?
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .notchGlass(in: Capsule(), tint: tint, interactive: true)
        .hoverScale(1.04)
    }
}
