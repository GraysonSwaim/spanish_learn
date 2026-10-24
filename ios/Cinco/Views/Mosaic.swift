import SwiftUI

/// A word's wall: blocks in the tones of one Barragán hue, cut with quarter circles, arches and suns, one
/// bright block from another hue, a faint shadow and print grain. Drawn from the word alone, so it looks the
/// same on every device and at any size, and the picture becomes part of remembering the word.
/// A port of the design canvas's Mosaico.dc.html, roll for roll: change one and change the other.
struct Mosaic: View {
    let word: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let plan = MosaicPlan(word: word, aspect: size.height / max(w, 1))
            for p in plan.pieces {
                let r = CGRect(x: p.rect.minX * w, y: p.rect.minY * w, width: p.rect.width * w, height: p.rect.height * w)
                // Blocks overlap by half a point, so no hairline shows where two meet.
                let shape = if case .block = p.shape { Path(r.insetBy(dx: -0.5, dy: -0.5)) } else { p.shape.path(in: r) }
                ctx.fill(shape, with: .color(p.color))
            }
            var shadow = Path()
            shadow.addLines(plan.shadow.map { CGPoint(x: $0.x * w, y: $0.y * size.height) })
            shadow.closeSubpath()
            ctx.fill(shadow, with: .color(Color(red: 0.1, green: 0.08, blue: 0.06).opacity(0.07)))
            var grain = ctx
            grain.blendMode = .multiply
            grain.opacity = 0.35
            grain.fill(Path(CGRect(origin: .zero, size: size)), with: .tiledImage(Grain.image, scale: 0.5))
            if scheme == .dark { ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.22))) }
        }
        .accessibilityHidden(true)
    }

    /// The seed for a mosaic that changes once a day, for Inicio and the end of a session.
    static var today: String { Date.now.formatted(.iso8601.year().month().day()) }
}

/// The blocks and shapes for one word, in unit space: width 1, height `aspect`.
nonisolated struct MosaicPlan {
    enum Shape {
        case block, sun, arch
        /// A quarter disc centred on a corner of its square: 0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right.
        case quarter(Int)

        func path(in r: CGRect) -> Path {
            switch self {
            case .block: return Path(r)
            case .sun: return Path(ellipseIn: r)
            case .arch:
                var p = Path()
                p.move(to: CGPoint(x: r.minX, y: r.maxY))
                p.addRelativeArc(center: CGPoint(x: r.midX, y: r.maxY), radius: r.width / 2, startAngle: .degrees(180), delta: .degrees(180))
                p.closeSubpath()
                return p
            case .quarter(let corner):
                let c = CGPoint(x: corner % 2 == 0 ? r.minX : r.maxX, y: corner < 2 ? r.minY : r.maxY)
                let start: Double = [0, 90, 270, 180][corner]
                var p = Path()
                p.move(to: c)
                p.addRelativeArc(center: c, radius: r.width, startAngle: .degrees(start), delta: .degrees(90))
                p.closeSubpath()
                return p
            }
        }
    }

    struct Piece {
        let rect: CGRect
        /// Hue, saturation and lightness, as the canvas writes them.
        let hsl: (h: Double, s: Double, l: Double)
        let shape: Shape
        var color: Color { MosaicPlan.hsl(hsl.h, hsl.s, hsl.l) }
    }

    /// Each family's deep, mid and light tones (hue, saturation, lightness): rosa mexicano, cempasúchil,
    /// jacaranda, cobalto, nopal, chile.
    static let families: [[(Double, Double, Double)]] = [
        [(330, 62, 36), (330, 70, 56), (330, 55, 84)],
        [(36, 78, 42), (38, 85, 58), (40, 75, 85)],
        [(262, 38, 30), (262, 42, 52), (262, 34, 84)],
        [(218, 58, 28), (214, 62, 50), (210, 48, 85)],
        [(160, 40, 24), (158, 32, 42), (150, 24, 82)],
        [(8, 62, 40), (10, 75, 58), (14, 65, 86)],
    ]

    private(set) var pieces: [Piece] = []
    /// The shadow's corners, as fractions of the width and height.
    private(set) var shadow: [CGPoint] = []

    init(word: String, aspect: Double) {
        let rng = Rng(word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        let fi = rng.int(6)
        let fam = Self.families[fi]
        let pop = Self.families[(fi + 2 + rng.int(3)) % 6][1]
        func col(_ c: (Double, Double, Double)) -> (h: Double, s: Double, l: Double) {
            ((c.0 + rng.jit(4)).rounded(), (c.1 + rng.jit(4)).rounded(), ((c.2 + rng.jit(2)) * 10).rounded() / 10)
        }

        var leaves: [CGRect] = []
        func split(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ d: Int) {
            if d >= 4 || (w < 0.36 && h < 0.36) || (d >= 2 && rng.next() < 0.3) {
                leaves.append(CGRect(x: x, y: y, width: w, height: h))
                return
            }
            let vert = w > h * 1.15 ? true : h > w * 1.15 ? false : rng.next() < 0.5
            let k = [0.34, 0.5, 0.62, 0.38, 0.66][rng.int(5)]
            if vert {
                split(x, y, w * k, h, d + 1); split(x + w * k, y, w * (1 - k), h, d + 1)
            } else {
                split(x, y, w, h * k, d + 1); split(x, y + h * k, w, h * (1 - k), d + 1)
            }
        }
        split(0, 0, 1, aspect, 0)

        let popAt = rng.int(leaves.count)
        // Tones run light-heavy so the wall stays quiet.
        let order = [2, 1, 2, 0, 2, 1]
        var motifs: [Piece] = []
        for (i, b) in leaves.enumerated() {
            let tone = order[(i + rng.int(2)) % order.count]
            pieces.append(Piece(rect: b, hsl: i == popAt ? col(pop) : col(fam[tone]), shape: .block))
            let other = col(fam[tone == 2 ? rng.int(2) : 2])
            let m = rng.next()
            let sz = min(b.width, b.height)
            if m < 0.34 {
                let corner = rng.int(4)
                let x = corner % 2 == 0 ? b.minX : b.maxX - sz, y = corner < 2 ? b.minY : b.maxY - sz
                motifs.append(Piece(rect: CGRect(x: x, y: y, width: sz, height: sz), hsl: other, shape: .quarter(corner)))
            } else if m < 0.5 && b.height > b.width * 0.45 {
                let d = min(b.width * 0.7, b.height * 1.4)
                motifs.append(Piece(rect: CGRect(x: b.minX + (b.width - d) / 2, y: b.maxY - d / 2, width: d, height: d / 2), hsl: other, shape: .arch))
            } else if m < 0.62 {
                let d = sz * 0.56
                motifs.append(Piece(rect: CGRect(x: b.midX - d / 2, y: b.midY - d / 2, width: d, height: d),
                                    hsl: i == popAt ? col(fam[2]) : col(pop), shape: .sun))
            }
        }
        pieces += motifs

        let x = Double(30 + rng.int(40)) / 100
        shadow = rng.next() < 0.5 ? [CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: x, y: 1)]
                                  : [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1 - x, y: 1)]
    }

    static func hsl(_ h: Double, _ s: Double, _ l: Double) -> Color {
        let s = s / 100, l = l / 100
        let c = (1 - abs(2 * l - 1)) * s
        let hp = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double) = switch hp {
        case ..<1: (c, x, 0)
        case ..<2: (x, c, 0)
        case ..<3: (0, c, x)
        case ..<4: (0, x, c)
        case ..<5: (x, 0, c)
        default: (c, 0, x)
        }
        let m = l - c / 2
        return Color(red: r + m, green: g + m, blue: b + m)
    }

    /// FNV-1a over the word's UTF-16, seeding mulberry32: the same rolls as JavaScript's.
    final class Rng {
        private var seed: UInt32

        init(_ s: String) {
            var h: UInt32 = 2166136261
            for u in s.utf16 { h ^= UInt32(u); h = h &* 16777619 }
            seed = h
        }

        func next() -> Double {
            seed = seed &+ 0x6D2B79F5
            var t = (seed ^ (seed >> 15)) &* (1 | seed)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Double(t ^ (t >> 14)) / 4294967296
        }

        func int(_ n: Int) -> Int { Int(next() * Double(n)) }

        func jit(_ a: Double) -> Double { (next() * 2 - 1) * a }
    }
}

/// A tile of grey noise, multiplied over a mosaic for the grain of a print. Made once, from a fixed seed.
private enum Grain {
    static let image: Image = {
        let n = 128
        var px = [UInt8](repeating: 0, count: n * n)
        var s: UInt32 = 0x9E3779B9
        for i in px.indices {
            s ^= s << 13; s ^= s >> 17; s ^= s << 5
            px[i] = 140 + UInt8(s % 116)
        }
        let cg = px.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)?.makeImage()
        }
        return cg.map { Image(decorative: $0, scale: 1) } ?? Image(systemName: "square")
    }()
}
