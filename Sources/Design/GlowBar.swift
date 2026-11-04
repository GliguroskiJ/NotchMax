import SwiftUI

/// Animace po zapojení nabíječky. Kreslí se přesně po vnějším obrysu zavřeného notche
/// (vlevo nahoře → dolů → po spodní hraně → nahoru doprava). Světelné pulzy běží zleva doprava
/// až k bodu, který odpovídá aktuálnímu nabití baterie, a zanechávají za sebou zelenou stopu;
/// koncový bod pulzuje. Řízeno časem přes `vm.chargeStart` (nezávisí na SwiftUI přechodech).
struct ChargeSweep: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var battery: BatteryMonitor
    let top: CGFloat
    let bottom: CGFloat

    /// Celková délka animace v sekundách (včetně dohasnutí).
    static let duration: Double = 3.5
    /// Okraj plátna kolem tvaru – místo pro záři a pro obrys posunutý ven.
    private static let margin: CGFloat = 24

    var body: some View {
        if let start = vm.chargeStart {
            let level: Double = battery.hasBattery ? Double(battery.level) / 100 : 1
            let fraction: CGFloat = CGFloat(min(max(level, 0.03), 1))
            let insetLeft: CGFloat = CGFloat(settings.chargeInsetLeft)
            let insetRight: CGFloat = CGFloat(settings.chargeInsetRight)
            let top = self.top
            let bottom = self.bottom
            TimelineView(.animation) { context in
                let elapsed: Double = context.date.timeIntervalSince(start)
                Canvas { gc, size in
                    ChargeSweep.draw(in: gc, size: size, top: top, bottom: bottom,
                                     insetLeft: insetLeft, insetRight: insetRight,
                                     elapsed: elapsed, fraction: fraction)
                }
                .padding(-ChargeSweep.margin)
            }
            .allowsHitTesting(false)
        }
    }

    private static func draw(in gc: GraphicsContext, size: CGSize, top: CGFloat, bottom: CGFloat,
                             insetLeft: CGFloat, insetRight: CGFloat,
                             elapsed e: Double, fraction f: CGFloat) {
        let rect = CGRect(x: margin, y: margin,
                          width: size.width - 2 * margin, height: size.height - 2 * margin)
        guard rect.width > 0, rect.height > 0 else { return }

        // Rychlé rozsvícení, na konci (3,0–3,5 s) dohasnutí.
        let fadeIn: Double = min(max(e / 0.15, 0), 1)
        let fadeOut: Double = e < 3.0 ? 1 : max(0, 1 - (e - 3.0) / 0.5)
        let fade: Double = fadeIn * fadeOut
        guard fade > 0 else { return }

        let outline = NotchPath.chargeOutline(in: rect, top: top, bottom: bottom,
                                              insetLeft: insetLeft, insetRight: insetRight)
        // Začátek cesty (levý horní roh obrysu).
        let startPoint = CGPoint(x: rect.minX + insetLeft, y: rect.minY)

        // 1) Stopa: během ~1,1 s doroste k bodu nabití (ease-out), pak zůstává.
        let grow: Double = min(max(e / 1.1, 0), 1)
        let eased: Double = 1 - pow(1 - grow, 3)
        let head: CGFloat = f * CGFloat(eased)
        guard head > 0.001 else { return }
        let trail = outline.trimmedPath(from: 0, to: head)
        let headPoint: CGPoint = trail.currentPoint ?? startPoint
        let gradientEnd = CGPoint(x: max(headPoint.x, startPoint.x + 1), y: headPoint.y)

        var trailGlow = gc
        trailGlow.opacity = fade * 0.75
        trailGlow.addFilter(.blur(radius: 5))
        trailGlow.stroke(trail, with: .color(Color.green),
                         style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))

        var trailLine = gc
        trailLine.opacity = fade
        trailLine.stroke(
            trail,
            with: .linearGradient(Gradient(colors: [Color.green.opacity(0.45), Color.green, Color.mint]),
                                  startPoint: startPoint, endPoint: gradientEnd),
            style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
        )

        // 2) Světelné pulzy: opakovaně vyráží ze začátku a dobíhají ke konci stopy.
        let spawnInterval: Double = 0.45
        let travel: Double = 0.95
        let pulseLength: CGFloat = 0.07
        for i in 0..<5 {
            let u: Double = (e - Double(i) * spawnInterval) / travel
            if u <= 0 || u >= 1 { continue }
            let smooth: Double = u * u * (3 - 2 * u)
            let p: CGFloat = min(f * CGFloat(smooth), head)
            let from: CGFloat = max(0, p - pulseLength)
            if p - from < 0.002 { continue }
            let segment = outline.trimmedPath(from: from, to: p)
            let segStart: CGPoint = from > 0
                ? (outline.trimmedPath(from: 0, to: from).currentPoint ?? startPoint)
                : startPoint
            let segEnd: CGPoint = segment.currentPoint ?? segStart
            let alpha: Double = fade * sin(Double.pi * u)

            var pulseGlow = gc
            pulseGlow.opacity = alpha * 0.9
            pulseGlow.addFilter(.blur(radius: 4))
            pulseGlow.stroke(segment, with: .color(Color.mint),
                             style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))

            var pulseCore = gc
            pulseCore.opacity = alpha
            pulseCore.stroke(
                segment,
                with: .linearGradient(Gradient(colors: [Color.mint.opacity(0), Color.white]),
                                      startPoint: segStart, endPoint: segEnd),
                style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)
            )
        }

        // 3) Koncový bod = aktuální nabití. Po doběhnutí stopy pulzuje.
        let arrived: Double = min(max((e - 0.9) / 0.4, 0), 1)
        let beat: Double = 0.5 + 0.5 * sin((e - 1.1) * 2 * Double.pi * 1.4)
        let swell: CGFloat = CGFloat(arrived * beat)
        let dotRadius: CGFloat = 2.4 + 1.3 * swell
        let haloRadius: CGFloat = 6 + 4 * swell

        var halo = gc
        halo.opacity = fade * (0.45 + 0.4 * arrived * beat)
        halo.addFilter(.blur(radius: 5))
        halo.fill(Path(ellipseIn: CGRect(x: headPoint.x - haloRadius, y: headPoint.y - haloRadius,
                                         width: haloRadius * 2, height: haloRadius * 2)),
                  with: .color(Color.green))

        var dot = gc
        dot.opacity = fade
        dot.fill(Path(ellipseIn: CGRect(x: headPoint.x - dotRadius, y: headPoint.y - dotRadius,
                                        width: dotRadius * 2, height: dotRadius * 2)),
                 with: .color(Color.white))
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
