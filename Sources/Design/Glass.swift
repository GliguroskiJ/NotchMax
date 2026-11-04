import SwiftUI

// MARK: - Deterministické „Liquid Glass“
//
// Nativní `glassEffect` (macOS 26) i NSVisualEffectView/materiály mění vzhled podle toho,
// jestli je okno klíčové / aplikace aktivní. Panel u notche klíčový nikdy není, a uživatel
// chce vzhled vždy stejný – proto sklo kreslíme sami jen z tvarů a přechodů SwiftUI.
// Výsledek nezávisí na stavu okna ani na verzi systému.

/// Vzhled skla pro malé ovládací prvky (kapsle, kulatá tlačítka): světlejší, lesklé.
struct ControlGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .clipShape(shape)
            .background(glassLayers)
            .overlay(rim.allowsHitTesting(false))
            .animation(.smooth(duration: 0.18), value: hovering)
            .onHover { inside in
                if interactive { hovering = inside }
            }
    }

    private var glassLayers: some View {
        ZStack {
            // Základ: průsvitná bílá (při omezené průhlednosti téměř neprůhledná šedá).
            shape
                .fill(reduceTransparency ? Color(white: 0.22) : Color.white.opacity(0.12))
                .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 2)
            if let tint {
                shape.fill(tint)
            }
            // Horní zrcadlový odlesk.
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(reduceTransparency ? 0.10 : 0.20), location: 0),
                        .init(color: Color.white.opacity(0.04), location: 0.45),
                        .init(color: Color.white.opacity(0), location: 0.6)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            // Spodní vnitřní záře – dojem tloušťky skla.
            shape.fill(
                LinearGradient(
                    colors: [Color.white.opacity(0), Color.white.opacity(0.07)],
                    startPoint: .center, endPoint: .bottom
                )
            )
            // Měkký vnitřní okraj (lom světla na hraně).
            shape
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 2)
                .blur(radius: 1.5)
                .clipShape(shape)
            // Zesvětlení při najetí myší.
            if interactive {
                shape.fill(Color.white.opacity(hovering ? 0.07 : 0))
            }
        }
    }

    private var rim: some View {
        shape.strokeBorder(
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.65), location: 0),
                    .init(color: Color.white.opacity(0.18), location: 0.4),
                    .init(color: Color.white.opacity(0.06), location: 0.7),
                    .init(color: Color.white.opacity(0.16), location: 1)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            lineWidth: 0.8
        )
    }
}

/// Vzhled velkých karet: tmavé, nenápadné, s jemným světlým obrysem.
struct CardGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .clipShape(shape)
            .background(
                ZStack {
                    shape.fill(Color.black.opacity(reduceTransparency ? 0.6 : 0.3))
                    shape.fill(Color.white.opacity(0.05))
                    shape.fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.05), Color.white.opacity(0)],
                            startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.35)
                        )
                    )
                }
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.14), Color.white.opacity(0.07)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
                .allowsHitTesting(false)
            )
    }
}

extension View {
    /// Sklo pro malé ovládací prvky (ne pro velké plochy a ne pro celý notch).
    @ViewBuilder
    func notchGlass<S: InsettableShape>(in shape: S, tint: Color? = nil, interactive: Bool = false, enabled: Bool = true) -> some View {
        if enabled {
            self.modifier(ControlGlass(shape: shape, tint: tint, interactive: interactive))
        } else {
            self
        }
    }

    /// Karta (tmavé sklo) se standardním odsazením.
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
            .modifier(CardGlass(shape: shape))
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

/// Dříve seskupovalo nativní sklo; vlastní sklo seskupení nepotřebuje, kontejner jen
/// vykreslí obsah (API zůstává kvůli volajícím).
struct GlassContainer<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
    }
}

/// Styl tlačítka se sklem: sklo se při stisku jemně zmenší a zesvětlí.
struct NotchGlassButtonStyle<S: InsettableShape>: ButtonStyle {
    let shape: S
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .notchGlass(in: shape, tint: tint, interactive: true)
            .overlay(
                shape.fill(Color.white.opacity(configuration.isPressed ? 0.08 : 0))
                    .allowsHitTesting(false)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.smooth(duration: 0.12), value: configuration.isPressed)
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
        .buttonStyle(NotchGlassButtonStyle(shape: Circle(),
                                           tint: prominent ? (tint ?? Color.white.opacity(0.18)) : nil))
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
                Text(L(title)).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .contentShape(Capsule())
        }
        .buttonStyle(NotchGlassButtonStyle(shape: Capsule(), tint: tint))
        .hoverScale(1.04)
    }
}

/// Kulaté skleněné tlačítko pro ovládání přehrávání. Každé tlačítko má vlastní sklo
/// (bez společné kapsle); zvýrazněné (play/pauza) je větší a podbarvené.
struct GlassTransportButton: View {
    let symbol: String
    var size: CGFloat = 30
    var prominent = false
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * (prominent ? 0.4 : 0.36), weight: .bold))
                .foregroundStyle(Color.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(NotchGlassButtonStyle(shape: Circle(),
                                           tint: prominent ? (tint ?? Color.white.opacity(0.22)) : nil))
        .hoverScale(prominent ? 1.06 : 1.08)
        .animation(.smooth(duration: 0.2), value: symbol)
    }
}
