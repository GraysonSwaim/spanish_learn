import SwiftUI
import UIKit

/// Barragán en calma: plaster and ink, and the mosaic's hue families (rosa mexicano, cempasúchil, cobalto,
/// nopal, jacaranda) for the stages, as light/dark pairs. Colour lives in the mosaics; the rest stays quiet.
/// Nonisolated: SwiftUI resolves colours on its render thread during animations, and a main-actor
/// colour provider there trips Swift's isolation check and crashes the app.
nonisolated enum Palette {
    static let bg = dyn(0xF2EDE8, 0x15120F)
    static let paper = dyn(0xF8F5F1, 0x1F1A16)
    static let sunk = dyn(0xE9E2DA, 0x1A1612)
    static let ink = dyn(0x2A211C, 0xF2EDE8)
    static let muted = dyn(0x6E625A, 0xADA096)
    static let line = dyn(0xE2DAD1, 0x2E2722)
    /// The hairline round cards and panels.
    static let edge = dyn(0xD9D0C7, 0x3A322B)
    /// What's left of the shadows: next to nothing, as the surfaces lie flat.
    static let shadow = dyn(0x2A211C, 0x000000, alpha: (0.05, 0.3))
    /// Rosa mexicano, deepened: the + button and links.
    static let accent = dyn(0xA84C72, 0xC75E8A)
    static let accentInk = dyn(0xA84C72, 0xE79AB9)
    /// Cobalto, then jacaranda for English.
    static let sea = dyn(0x2D5DA8, 0x8DB0EA)
    static let seaSoft = dyn(0xDCE5F3, 0x1C2A40)
    static let blue = dyn(0x4A3A86, 0xB9AEEB)
    static let good = dyn(0x3F6E58, 0x6FB394)
    static let onGood = dyn(0xFFFFFF, 0x0F1F18)
    static let goodSoft = dyn(0xDCEAE2, 0x1B3127)
    static let again = dyn(0xB5473A, 0xF08A7A)
    static let againSoft = dyn(0xF4DDD8, 0x3F221D)
    /// English text.
    static let en = blue
    /// The stages, in the mosaic's mid tones: rosa, cempasúchil, cobalto, nopal, jacaranda.
    static let stages = [dyn(0xDD408F, 0xE56CA8), dyn(0xEFAC39, 0xF3C068), dyn(0x3075CF, 0x5A91D8),
                         dyn(0x498D74, 0x5DAC8F), dyn(0x7751B8, 0x9375C7)]
    /// The same five in their light tones, as fills.
    static let stagesSoft = [dyn(0xEDC0D6, 0x492738), dyn(0xF5E2BC, 0x493E27), dyn(0xC6D9EB, 0x273849),
                             dyn(0xC6DCD1, 0x274938), dyn(0xD3C8E4, 0x342749)]
    static let near = dyn(0xEFAC39, 0xF3C068)
    /// A highlighter: words marked in a reading.
    static let mark = dyn(0xF2D9A6, 0x765E2D)

    /// Theme colours, as a strong mark and a soft card fill: the stages, then cobalto.
    nonisolated static let chunkCount = 6
    private static let chunks: [(Color, Color)] = [
        (stages[0], stagesSoft[0]), (stages[1], stagesSoft[1]), (stages[2], stagesSoft[2]),
        (stages[3], stagesSoft[3]), (stages[4], stagesSoft[4]), (sea, seaSoft),
    ]

    static func chunk(_ i: Int) -> (mark: Color, fill: Color) {
        let c = chunks[((i % chunkCount) + chunkCount) % chunkCount]
        return (c.0, c.1)
    }

    static func mood(_ m: Mood) -> Color {
        switch m {
        case .ind: sea
        case .sub: stages[4]
        case .imp: stages[0]
        }
    }

    static func moodSoft(_ m: Mood) -> Color {
        switch m {
        case .ind: seaSoft
        case .sub: stagesSoft[4]
        case .imp: stagesSoft[0]
        }
    }

    static func stage(_ i: Int) -> Color { stages[max(1, min(5, i)) - 1] }
    static func stageSoft(_ i: Int) -> Color { stagesSoft[max(1, min(5, i)) - 1] }

    private static func dyn(_ light: UInt32, _ dark: UInt32, alpha: (CGFloat, CGFloat) = (1, 1)) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? rgb(dark, alpha.1) : rgb(light, alpha.0) })
    }

    private static func rgb(_ v: UInt32, _ a: CGFloat) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
    }
}

/// Bricolage Grotesque throughout, bundled: its 96pt cut for big display type, the text cut below that.
enum Typo {
    static func display(_ size: CGFloat) -> Font {
        .custom(size > 30 ? "BricolageGrotesque96pt-Bold" : "BricolageGrotesque-Bold", size: size, relativeTo: .title)
    }

    static func text(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        let name = switch weight {
        case .bold, .semibold: "BricolageGrotesque-SemiBold"
        case .heavy, .black: "BricolageGrotesque-Bold"
        default: "BricolageGrotesque-Medium"
        }
        return .custom(name, size: size, relativeTo: .body)
    }

    /// Example sentences: upright, as Bricolage has no italic. They're told apart by colour and place instead.
    static func sentence(_ size: CGFloat) -> Font { .custom("BricolageGrotesque-Medium", size: size, relativeTo: .body) }
}

/// The plaster page behind every screen.
struct Backdrop: View {
    var body: some View {
        Palette.bg.ignoresSafeArea()
    }
}

/// A flat plane of colour, like a wall in the sun: no sheen, no shadow. `lift` dips it a shade as it's
/// pressed. (`shade` and `eoFill` are kept for the callers from the glossy look.)
struct Gloss<S: Shape>: View {
    let color: Color
    let shape: S
    var shade: CGFloat = 1
    var lift: CGFloat = 1
    var eoFill = false

    var body: some View {
        shape.fill(color.mix(with: .black, by: lift < 0.5 ? 0.08 : 0), style: FillStyle(eoFill: eoFill))
    }
}

/// A flat button with small square corners, darkening a little as it's pressed.
struct SoftButtonStyle: ButtonStyle {
    var fill: Color = Palette.paper
    var text: Color = Palette.ink
    var radius: CGFloat = 6
    var size: CGFloat = 21

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: min(radius, 6))
        let plain = fill == Palette.paper
        configuration.label
            .font(Typo.display(size))
            .foregroundStyle(text)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .padding(.horizontal, 12)
            .background { Gloss(color: fill, shape: shape, lift: down ? 0.3 : 1) }
            .overlay { if plain { shape.strokeBorder(Palette.edge, lineWidth: 1.5) } }
            .scaleEffect(down ? 0.985 : 1)
            .animation(.spring(duration: 0.18), value: down)
    }
}

extension View {
    /// The panel the cards and menus use: paper with a hairline, lying flat.
    func panel(radius: CGFloat = 6, shadow: CGFloat = 4) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(radius, 6))
        return self
            .background(Palette.paper, in: shape)
            .overlay(shape.strokeBorder(Palette.edge, lineWidth: 1))
    }

    func softShadow(radius: CGFloat = 14, y: CGFloat = 6) -> some View {
        shadow(color: Palette.shadow, radius: radius, y: y)
    }
}

/// Five bars rising like steps, inked up to a card's stage, with its name.
struct StageTiles: View {
    let stage: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(1...5, id: \.self) { i in
                Rectangle()
                    .fill(Palette.ink.opacity(i <= stage ? 1 : 0.15))
                    .frame(width: 8, height: CGFloat(6 + 4 * i))
            }
            Text(stage > 0 ? "Etapa \(stage) · \(StageInfo.all[stage].name)" : "Nueva")
                .font(Typo.text(14, .bold))
                .foregroundStyle(Palette.muted)
                .padding(.leading, 6)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A segmented switch: a sunk track whose chosen option is a flat paper block.
struct SoftSegmented<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var size: CGFloat = 16
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { o in
                let on = o.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selection = o.value }
                } label: {
                    Text(o.label)
                        .font(Typo.text(size, on ? .heavy : .bold))
                        .foregroundStyle(on ? Palette.ink : Palette.muted)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 4).fill(Palette.paper)
                                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.edge, lineWidth: 1))
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Palette.sunk, in: .rect(cornerRadius: 6))
    }
}
