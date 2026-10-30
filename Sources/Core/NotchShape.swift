import SwiftUI

/// Geometrie tvaru notche: horní rohy se zakřivují směrem ven (splynutí s menu barem),
/// spodní rohy jsou zaoblené.
enum NotchPath {
    static func make(in rect: CGRect, top: CGFloat, bottom: CGFloat, closed: Bool) -> Path {
        var p = Path()
        let t = max(0, min(top, rect.height / 2))
        let b = max(0, min(bottom, rect.height - t))
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                       control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                       control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                       control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - t, y: rect.minY))
        if closed { p.closeSubpath() }
        return p
    }
}

/// Uzavřený tvar pro výplň (černé pozadí notche).
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        NotchPath.make(in: rect, top: topRadius, bottom: bottomRadius, closed: true)
    }
}

/// Otevřený obrys (bez horní hrany) pro glow, nabíjecí sweep a progress.
struct NotchOutline: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        NotchPath.make(in: rect, top: topRadius, bottom: bottomRadius, closed: false)
    }
}
