import SwiftUI

/// Rafiq's look, in one place: a dome that rises to a point, like a lantern's cap, on a
/// soft, squarer base; ivory to sand; a small golden crescent on top; warm golden cheeks.
/// Every view that draws the companion (the island, the pills, the upload box, the
/// wardrobe icons, the iPhone) takes its silhouette and its colours from here.
enum RafiqLook {
    /// How far the dome rises above the base, in units of the half height.
    static let domeHeight: CGFloat = 1.3
    /// How the dome narrows towards its point (higher: rounder shoulders).
    static let domeTaper: CGFloat = 2.0
    /// How the dome's sides curve in near the point (higher: a finer point).
    static let domeCurve: CGFloat = 1.4
    /// The base: a superellipse, squarer than a circle.
    static let baseExponent: CGFloat = 3.2

    static let bodyTopCG = CGColor(red: 0.984, green: 0.965, blue: 0.925, alpha: 1)     // #FBF6EC
    static let bodyBottomCG = CGColor(red: 0.871, green: 0.804, blue: 0.690, alpha: 1)  // #DECDB0
    static let inkCG = CGColor(red: 0.075, green: 0.129, blue: 0.247, alpha: 1)         // #13213F
    static let goldCG = CGColor(red: 0.910, green: 0.714, blue: 0.290, alpha: 1)        // #E8B64A

    static var bodyTop: Color { Color(cgColor: bodyTopCG) }
    static var bodyBottom: Color { Color(cgColor: bodyBottomCG) }
    static var gold: Color { Color(cgColor: goldCG) }

    /// Inside the silhouette, centred on the origin, y down.
    static func contains(x: CGFloat, y: CGFloat, rx: CGFloat, ry: CGFloat) -> Bool {
        guard rx > 0, ry > 0 else { return false }
        if y >= 0 {
            return pow(abs(x / rx), baseExponent) + pow(abs(y / ry), baseExponent) <= 1
        }
        let t = -y / (ry * domeHeight)
        if t >= 1 { return false }
        return abs(x) <= rx * pow(1 - pow(t, domeTaper), domeCurve)
    }

    /// The edge of the silhouette in the direction (ca, sa). Every ray from the centre
    /// crosses the edge once, so a bisection finds it.
    static func point(ca: CGFloat, sa: CGFloat, rx: CGFloat, ry: CGFloat) -> CGPoint {
        var lo: CGFloat = 0
        var hi = max(rx, ry * domeHeight) * 1.05
        for _ in 0..<18 {
            let mid = (lo + hi) / 2
            if contains(x: ca * mid, y: sa * mid, rx: rx, ry: ry) { lo = mid } else { hi = mid }
        }
        return CGPoint(x: ca * lo, y: sa * lo)
    }

    /// The closed silhouette, `points` steps around.
    static func path(rx: CGFloat, ry: CGFloat, points: Int = 96) -> Path {
        var p = Path()
        for i in 0...points {
            let a = CGFloat(i) / CGFloat(points) * .pi * 2
            let pt = point(ca: cos(a), sa: sin(a), rx: rx, ry: ry)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    /// The top of the dome.
    static func tip(ry: CGFloat) -> CGPoint { CGPoint(x: 0, y: -ry * domeHeight) }

    /// The small golden ball and crescent above the point of the dome.
    /// `R` is the body's unit; `opacity` fades it out (an outfit on, the upload box).
    static func drawFinial(_ ctx: GraphicsContext, ry: CGFloat, R: CGFloat, opacity: Double = 1) {
        guard opacity > 0.01 else { return }
        let tipY = tip(ry: ry).y
        var c = ctx
        c.opacity = opacity
        // The ball, sitting on the point.
        let ball = R * 0.065
        c.fill(Path(ellipseIn: CGRect(x: -ball, y: tipY - R * 0.05 - ball * 2, width: ball * 2, height: ball * 2)),
               with: .color(gold))
        // The crescent: a disc with a smaller disc taken out, opening to the upper right.
        let r = R * 0.12
        let center = CGPoint(x: 0, y: tipY - R * 0.27)
        var crescent = c
        let cut = Path(ellipseIn: CGRect(x: center.x - r * 0.82 + r * 0.55, y: center.y - r * 0.82 - r * 0.2,
                                         width: r * 1.64, height: r * 1.64))
        crescent.clip(to: cut, options: .inverse)
        crescent.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                      with: .color(gold))
    }
}
