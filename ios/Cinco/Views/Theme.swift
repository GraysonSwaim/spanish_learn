import SwiftUI
import UIKit

/// The web app's palette, as light/dark pairs.
enum Palette {
    static let bg = dyn(0xFFE9C9, 0x0E2A28)
    static let paper = dyn(0xFFFFFF, 0x163B37)
    static let sunk = dyn(0xFFF6E8, 0x12332F)
    static let ink = dyn(0x12302A, 0xFFF1DE)
    static let muted = dyn(0x4F6A61, 0xA5C7BD)
    static let line = dyn(0xF2D3A8, 0x285A54)
    static let edge = dyn(0x12302A, 0x051412)
    static let accent = dyn(0xFF5A36, 0xFF6B47)
    static let accentInk = dyn(0xC93A18, 0xFF9474)
    static let sea = dyn(0x00B4C6, 0x2FD0E0)
    static let seaSoft = dyn(0xD4F4F7, 0x134A4E)
    static let good = dyn(0x00A67E, 0x2BC79A)
    static let onGood = dyn(0xFFFFFF, 0x062019)
    static let goodSoft = dyn(0xD2F3E8, 0x123F33)
    static let again = dyn(0xE8364F, 0xFF6275)
    static let againSoft = dyn(0xFFD6DA, 0x4A1C24)
    /// English text: blue in light, orange in dark.
    static let en = dyn(0x1F5BC9, 0xFFA24C)
    static let stages = [dyn(0xFF5A8C, 0xFF6F9C), dyn(0xFF9F1C, 0xFFAE3D), dyn(0x00B4C6, 0x22C8D8),
                         dyn(0x00A67E, 0x22BD8E), dyn(0x7B3FE4, 0x9A6BFF)]
    static let near = dyn(0xFF9F1C, 0xFFAE3D)

    static func mood(_ m: Mood) -> Color {
        switch m {
        case .ind: dyn(0x007F8C, 0x2FD0E0)
        case .sub: dyn(0x6A33D1, 0xB39BFF)
        case .imp: dyn(0xC2410C, 0xFFA25E)
        }
    }

    static func moodSoft(_ m: Mood) -> Color {
        switch m {
        case .ind: dyn(0xD6F2F4, 0x134A4E)
        case .sub: dyn(0xECE3FF, 0x2E2A55)
        case .imp: dyn(0xFFE6D5, 0x4A2E1C)
        }
    }

    static func stage(_ i: Int) -> Color { stages[max(1, min(5, i)) - 1] }

    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) })
    }

    private static func rgb(_ v: UInt32) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

/// Lilita One for display, Nunito for text, both bundled.
enum Typo {
    static func display(_ size: CGFloat) -> Font { .custom("LilitaOne", size: size, relativeTo: .title) }

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

/// The chunky button with a hard shadow under it that sinks when pressed.
struct ChunkyButtonStyle: ButtonStyle {
    var fill: Color = Palette.paper
    var text: Color = Palette.ink
    var radius: CGFloat = 22
    var size: CGFloat = 22

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: radius)
        configuration.label
            .font(Typo.display(size))
            .foregroundStyle(text)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .background(fill, in: shape)
            .offset(y: down ? 4 : 0)
            .background(shape.fill(Palette.edge).offset(y: 5))
            .animation(.easeOut(duration: 0.08), value: down)
    }
}

extension View {
    /// The bordered, hard-shadowed panel the cards and menus use.
    func panel(radius: CGFloat = 22, shadow: CGFloat = 4) -> some View {
        self
            .background(Palette.paper, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Palette.edge, lineWidth: 2))
            .background(Palette.edge.clipShape(.rect(cornerRadius: radius)).offset(y: shadow))
    }
}

/// Five little squares showing a card's stage, with its name.
struct StageTiles: View {
    let stage: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 5)
                    .fill(i <= stage ? Palette.stage(i) : Palette.paper)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.edge, lineWidth: 2))
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

/// The web app's segmented switch: a sunk, bordered track whose chosen option is a sea-blue pill,
/// with the hard shadow the panels and buttons use.
struct ChunkySegmented<Value: Hashable>: View {
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
                        .foregroundStyle(on ? .white : Palette.muted)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 10).fill(Palette.sea)
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
        .background(Palette.sunk, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.edge, lineWidth: 2))
        .background(Palette.edge.clipShape(.rect(cornerRadius: 14)).offset(y: 3))
    }
}
