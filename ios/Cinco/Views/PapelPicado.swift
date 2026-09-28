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

/// One flag: scalloped, with a row of dots cut out above the scallops and, unless it carries a letter,
/// a daisy in the middle.
nonisolated struct PapelFlag: Shape {
    var daisy = true

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        var p = Scalloped(radius: w * 0.08, scallop: w / 4).path(in: rect)
        if daisy {
            let d = w * 0.5
            p.addPath(Daisy().path(in: CGRect(x: rect.midX - d / 2, y: rect.minY + rect.height * 0.14, width: d, height: d)))
        }
        let dot = w * 0.07, y = rect.maxY - w * 0.3
        for i in 0..<4 {
            let x = rect.minX + w * (0.2 + 0.2 * CGFloat(i))
            p.addEllipse(in: CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot))
        }
        return p
    }
}

/// A string of flags in the five stage colours, sagging a little in the middle. Given letters, each flag
/// carries one, cut out of the paper the way papel picado banners spell a word.
struct Bunting: View {
    var count = 5
    var flag: CGFloat = 22
    var spacing: CGFloat = 5
    var letters: [String] = []

    var body: some View {
        let n = letters.isEmpty ? count : letters.count
        let width = CGFloat(n) * flag + CGFloat(n - 1) * spacing + flag * 0.6
        let sag = flag * (letters.isEmpty ? 0.35 : 0.18)
        let tilt = letters.isEmpty ? 3.0 : 2.0
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: .zero)
                p.addQuadCurve(to: CGPoint(x: width, y: 0), control: CGPoint(x: width / 2, y: sag * 2))
            }
            .stroke(Palette.muted.opacity(0.45), lineWidth: letters.isEmpty ? 1 : 1.5)
            ForEach(0..<n, id: \.self) { i in
                let x = flag * 0.3 + CGFloat(i) * (flag + spacing)
                let t = (x + flag / 2) / width
                flagView(i)
                    .frame(width: flag, height: flag * 1.2)
                    .rotationEffect(.degrees(i.isMultiple(of: 2) ? -tilt : tilt), anchor: .top)
                    // Papel picado folds over its string, so the flags start just above it.
                    .offset(x: x, y: sag * 4 * t * (1 - t) - 1.5)
            }
        }
        .frame(width: width, height: flag * 1.2 + sag, alignment: .topLeading)
    }

    @ViewBuilder private func flagView(_ i: Int) -> some View {
        let color = Palette.stage(i % 5 + 1)
        if i < letters.count {
            // The raised flag with its letter cut through, and the flag's own shadow falling into the cut.
            cut(Gloss(color: color, shape: PapelFlag(daisy: false), lift: 0.6, eoFill: true), letters[i])
                .background {
                    cut(PapelFlag(daisy: false).fill(.black.opacity(0.22)), letters[i])
                        .offset(y: 1.5).blur(radius: 0.8)
                }
        } else {
            Gloss(color: color, shape: PapelFlag(), lift: 0.4, eoFill: true)
        }
    }

    private func cut(_ paper: some View, _ letter: String) -> some View {
        paper
            .overlay {
                Text(letter)
                    .font(.custom("Nunito-ExtraBold", size: flag * 0.95, relativeTo: .largeTitle))
                    .offset(y: -flag * 0.12)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
    }
}

/// "choca cinco" as two papel picado banners, a small "choca" strung above "cinco": five letters and
/// five flags each, in the five stage colours.
struct Wordmark: View {
    var flag: CGFloat = 58

    var body: some View {
        VStack(spacing: flag * 0.08) {
            Bunting(flag: flag * 0.6, spacing: 4, letters: ["c", "h", "o", "c", "a"])
            Bunting(flag: flag, spacing: 5, letters: ["c", "i", "n", "c", "o"])
        }
        .accessibilityElement()
        .accessibilityLabel("Choca Cinco")
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    VStack(spacing: 30) {
        Wordmark()
        Bunting()
        Bunting(count: 7, flag: 36)
        HStack { ForEach(1...5, id: \.self) { Daisy().fill(Palette.stage($0)).frame(width: 18, height: 18) } }
        Scalloped().fill(Palette.stageSoft(2)).frame(width: 64, height: 140)
    }
    .padding()
    .background(Backdrop())
}
