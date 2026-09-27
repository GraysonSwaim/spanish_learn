import SwiftUI

// Papel picado, the cut-paper banners the app icon's 5 is made of: a daisy cutout, a scalloped edge,
// and little flags on a string. Used sparingly, as accents.

/// An eight-petal daisy, like the cutouts in the icon. The petals don't overlap, so it can also be
/// punched out of another shape with an even-odd fill.
nonisolated struct Daisy: Shape {
    var petals = 8

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        let inner = r * 0.3, width = r * 2 * .pi / Double(petals) * 0.62
        for i in 0..<petals {
            let angle = Double(i) / Double(petals) * 2 * .pi
            let petal = Path(ellipseIn: CGRect(x: -width / 2, y: inner, width: width, height: r - inner))
            p.addPath(petal, transform: CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle))
        }
        p.addEllipse(in: CGRect(x: c.x - r * 0.17, y: c.y - r * 0.17, width: r * 0.34, height: r * 0.34))
        return p
    }
}

/// A rectangle with rounded top corners and a scalloped bottom edge, like the foot of a papel picado flag.
nonisolated struct Scalloped: Shape {
    var radius: CGFloat = 16
    /// Roughly how wide each scallop is; the edge fits a whole number of them.
    var scallop: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        let depth = scallop * 0.35
        let n = max(1, Int((rect.width / scallop).rounded()))
        let step = rect.width / CGFloat(n)
        let base = rect.maxY - depth
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: base))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        p.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: base))
        for i in (0..<n).reversed() {
            let x0 = rect.minX + CGFloat(i) * step
            p.addQuadCurve(to: CGPoint(x: x0, y: base), control: CGPoint(x: x0 + step / 2, y: rect.maxY + depth))
        }
        p.closeSubpath()
        return p
    }
}

/// One flag: scalloped, with a daisy and a row of dots cut out of it.
nonisolated struct PapelFlag: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Scalloped(radius: rect.width * 0.08, scallop: rect.width / 4).path(in: rect)
        let d = rect.width * 0.5
        p.addPath(Daisy().path(in: CGRect(x: rect.midX - d / 2, y: rect.minY + rect.height * 0.14, width: d, height: d)))
        let dot = rect.width * 0.07, y = rect.maxY - rect.width * 0.3
        for i in 0..<4 {
            let x = rect.minX + rect.width * (0.2 + 0.2 * CGFloat(i))
            p.addEllipse(in: CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot))
        }
        return p
    }
}

/// A string of flags in the five stage colours, sagging a little in the middle.
struct Bunting: View {
    var count = 5
    var flag: CGFloat = 22
    var spacing: CGFloat = 5

    var body: some View {
        let width = CGFloat(count) * flag + CGFloat(count - 1) * spacing + flag * 0.6
        let sag = flag * 0.35
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: .zero)
                p.addQuadCurve(to: CGPoint(x: width, y: 0), control: CGPoint(x: width / 2, y: sag * 2))
            }
            .stroke(Palette.muted.opacity(0.45), lineWidth: 1)
            ForEach(0..<count, id: \.self) { i in
                let x = flag * 0.3 + CGFloat(i) * (flag + spacing)
                let t = (x + flag / 2) / width
                PapelFlag()
                    .fill(Palette.stage(i % 5 + 1), style: FillStyle(eoFill: true))
                    .frame(width: flag, height: flag * 1.2)
                    .rotationEffect(.degrees(i.isMultiple(of: 2) ? -3 : 3), anchor: .top)
                    .offset(x: x, y: sag * 4 * t * (1 - t))
            }
        }
        .frame(width: width, height: flag * 1.2 + sag, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 30) {
        Bunting()
        Bunting(count: 7, flag: 36)
        HStack { ForEach(1...5, id: \.self) { Daisy().fill(Palette.stage($0)).frame(width: 18, height: 18) } }
        Scalloped().fill(Palette.stageSoft(2)).frame(width: 64, height: 140)
    }
    .padding()
    .background(Backdrop())
}
