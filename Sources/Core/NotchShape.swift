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

    /// Otevřený obrys pro animaci nabíjení. Levá / pravá svislá část se posune o `insetLeft` /
    /// `insetRight` bodů dovnitř (kladné) nebo ven (záporné), aby šlo obrys doladit na fyzický notch.
    /// Cesta začíná vlevo nahoře, vede dolů, po spodní hraně a nahoru doprava.
    static func chargeOutline(in rect: CGRect, top: CGFloat, bottom: CGFloat,
                              insetLeft: CGFloat, insetRight: CGFloat) -> Path {
        let minWidth: CGFloat = 2 * top + 2 * bottom
        let width: CGFloat = max(rect.width - insetLeft - insetRight, minWidth)
        let r = CGRect(x: rect.minX + insetLeft, y: rect.minY, width: width, height: rect.height)
        return make(in: r, top: top, bottom: bottom, closed: false)
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

/// Otevřený obrys (bez horní hrany) – jemná linka kolem rozbaleného panelu.
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
