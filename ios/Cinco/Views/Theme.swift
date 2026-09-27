import SwiftUI
import UIKit

/// Warm cream and five soft stage colours, from the Cinco mockup, as light/dark pairs.
/// Nonisolated: SwiftUI resolves colours on its render thread during animations, and a main-actor
/// colour provider there trips Swift's isolation check and crashes the app.
nonisolated enum Palette {
    static let bg = dyn(0xF9F0E5, 0x1B1714)
    static let paper = dyn(0xFFFCF7, 0x27221E)
    static let sunk = dyn(0xF3E7D8, 0x221D1A)
    static let ink = dyn(0x2B2622, 0xF7EEE4)
    static let muted = dyn(0x7D7066, 0xB3A597)
    static let line = dyn(0xEBDDCC, 0x3A322C)
    /// The hairline round cards and panels.
    static let edge = dyn(0xEADBC8, 0x3D342E)
    /// Soft shadow under anything that floats.
    static let shadow = dyn(0x8A5A2B, 0x000000, alpha: (0.13, 0.5))
    /// The wordmark's coral, teal and blue.
    static let accent = dyn(0xEE6A4B, 0xDD5A3C)
    static let accentInk = dyn(0xC24E2F, 0xFFA084)
    static let sea = dyn(0x2A9D99, 0x4CC3BE)
    static let seaSoft = dyn(0xD8F0EE, 0x1D3B3A)
    static let blue = dyn(0x2A62A6, 0x8DB6F0)
    static let sun = dyn(0xF0A81C, 0xFFC94D)
    static let good = dyn(0x2E9E7B, 0x4CC49C)
    static let onGood = dyn(0xFFFFFF, 0x10231C)
    static let goodSoft = dyn(0xD9F1E6, 0x1C3A2F)
    static let again = dyn(0xE0554F, 0xFF7A72)
    static let againSoft = dyn(0xFBDAD5, 0x45221F)
    /// English text.
    static let en = blue
    /// The five cards of the mockup, in its circle's order: orange, yellow, mint, blue, lavender.
    static let stages = [dyn(0xF2803F, 0xFF9A5E), dyn(0xE9A514, 0xFFC94D), dyn(0x34A488, 0x5CCBA9),
                         dyn(0x3576C2, 0x6FA4E8), dyn(0x9063BF, 0xB48BE0)]
    /// The same five as pastel card fills.
    static let stagesSoft = [dyn(0xFCC9A6, 0x4A2E20), dyn(0xFFDF8A, 0x4A3D1C), dyn(0xBDE5D4, 0x1F3D34),
                             dyn(0xC1D6F1, 0x1F3047), dyn(0xDAC8EB, 0x362A45)]
    static let near = dyn(0xE9A514, 0xFFC94D)
    /// The soft light falling on the backdrop.
    static let glow = dyn(0xFFFFFF, 0xFFD9B0, alpha: (0.6, 0.06))

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

/// Nunito throughout, bundled: ExtraBold for display, like the wordmark.
enum Typo {
    static func display(_ size: CGFloat) -> Font { .custom("Nunito-ExtraBold", size: size, relativeTo: .title) }

    static func text(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        let name = switch weight {
        case .bold, .semibold: "Nunito-Bold"
        case .heavy, .black: "Nunito-ExtraBold"
        default: "Nunito-Medium"
        }
        return .custom(name, size: size, relativeTo: .body)
    }

    static func italic(_ size: CGFloat) -> Font { .custom("Nunito-MediumItalic", size: size, relativeTo: .body) }
}

/// The cream page with a soft light from the top, behind every screen.
struct Backdrop: View {
    var body: some View {
        Palette.bg
            .overlay(RadialGradient(colors: [Palette.glow, .clear], center: .init(x: 0.2, y: 0), startRadius: 0, endRadius: 520))
            .ignoresSafeArea()
    }
}

/// A soft pill button: a gentle sheen on top, a shadow tinted by its own colour, and a small press.
struct SoftButtonStyle: ButtonStyle {
    var fill: Color = Palette.paper
    var text: Color = Palette.ink
    var radius: CGFloat = 22
    var size: CGFloat = 21

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: radius)
        let plain = fill == Palette.paper
        configuration.label
            .font(Typo.display(size))
            .foregroundStyle(text)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .padding(.horizontal, 12)
            .background {
                shape.fill(fill)
                    .overlay(shape.fill(LinearGradient(colors: [.white.opacity(plain ? 0 : 0.22), .clear], startPoint: .top, endPoint: .center)))
                    .overlay(shape.strokeBorder(plain ? Palette.edge : .white.opacity(0.25), lineWidth: 1))
                    .shadow(color: plain ? Palette.shadow : fill.opacity(0.38), radius: down ? 6 : 14, y: down ? 3 : 8)
            }
            .scaleEffect(down ? 0.975 : 1)
            .animation(.spring(duration: 0.18), value: down)
    }
}

extension View {
    /// The floating panel the cards and menus use: paper, a hairline, and a soft shadow.
    func panel(radius: CGFloat = 24, shadow: CGFloat = 4) -> some View {
        self
            .background(Palette.paper, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Palette.edge, lineWidth: 1))
            .softShadow(radius: shadow * 4, y: shadow * 2)
    }

    func softShadow(radius: CGFloat = 14, y: CGFloat = 6) -> some View {
        shadow(color: Palette.shadow, radius: radius, y: y)
    }
}

/// Five little squares showing a card's stage, with its name.
struct StageTiles: View {
    let stage: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4)
                    .fill(i <= stage ? Palette.stage(i) : Palette.line)
                    .frame(width: 14, height: 14)
            }
            Text(stage > 0 ? "Etapa \(stage) · \(StageInfo.all[stage].name)" : "Nueva")
                .font(Typo.text(14, .bold))
                .foregroundStyle(Palette.muted)
                .padding(.leading, 8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A segmented switch: a sunk track whose chosen option is a raised paper pill.
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
                                RoundedRectangle(cornerRadius: 12).fill(Palette.paper)
                                    .softShadow(radius: 6, y: 2)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Palette.sunk, in: .rect(cornerRadius: 16))
    }
}
