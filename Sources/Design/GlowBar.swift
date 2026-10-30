import SwiftUI

/// Pulzující / rotující svítící obrys kolem notche. Volitelně jako ukazatel průběhu (progress).
struct GlowBar: View {
    let top: CGFloat
    let bottom: CGFloat
    let color: Color
    let style: GlowStyle
    var progress: Double?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let pulse = 0.5 + 0.5 * sin(t * 2 * .pi / 2.6)
            let outline = NotchOutline(topRadius: top, bottomRadius: bottom)
                .trim(from: 0, to: CGFloat(progress ?? 1))
            ZStack {
                outline.stroke(fill(t: t, pulse: pulse), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                outline.stroke(fill(t: t, pulse: pulse), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .blur(radius: 5)
                    .opacity(0.4 + 0.5 * pulse)
            }
        }
        .allowsHitTesting(false)
    }

    private func fill(t: Double, pulse: Double) -> AnyShapeStyle {
        switch style {
        case .aurora:
            return AnyShapeStyle(
                AngularGradient(
                    colors: [color, Color.white, color.opacity(0.25), color],
                    center: .center,
                    angle: .degrees(t * 70)
                )
            )
        case .minimal:
            return AnyShapeStyle(color.opacity(0.7))
        default:
            return AnyShapeStyle(color.opacity(0.45 + 0.55 * pulse))
        }
    }
}

/// Zelený „sweep“ kolem obrysu notche po zapojení nabíječky.
struct ChargeSweep: View {
    @EnvironmentObject private var vm: NotchViewModel
    let top: CGFloat
    let bottom: CGFloat

    var body: some View {
        if let start = vm.chargeStart {
            TimelineView(.animation) { context in
                let e: Double = context.date.timeIntervalSince(start)
                let draw: Double = min(max(e / 1.2, 0), 1)
                let eased: Double = draw < 0.5 ? 2 * draw * draw : 1 - pow(-2 * draw + 2, 2) / 2
                let fade: Double = e < 2.9 ? 1 : max(0, 1 - (e - 2.9) / 0.7)
                let pulse: Double = 0.75 + 0.25 * sin(e * 6)
                let outline = NotchOutline(topRadius: top, bottomRadius: bottom)
                    .trim(from: 0, to: CGFloat(eased))
                ZStack {
                    outline
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .blur(radius: 6)
                        .opacity(0.75 * pulse)
                    outline
                        .stroke(
                            LinearGradient(colors: [Color.green, Color.mint, Color.white],
                                           startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                        )
                }
                .opacity(fade)
            }
            .allowsHitTesting(false)
        }
    }
}

/// Ekvalizér jen jako vizuální prvek (nereaguje na skutečný zvuk).
struct EqualizerBars: View {
    var color: Color
    var active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let phase: Double = t * (2.2 + Double(i) * 0.7) + Double(i)
                    let barHeight: CGFloat = active ? CGFloat(4 + 10 * abs(sin(phase))) : 3
                    Capsule()
                        .fill(color)
                        .frame(width: 2.5, height: barHeight)
                }
            }
            .frame(height: 16)
        }
    }
}
