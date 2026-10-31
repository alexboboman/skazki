import SwiftUI
import SkazochnikCore

/// Friendly child built from simple shapes; a port of `HeroAvatar` in docs/design/prototype/ui.jsx.
public struct HeroAvatarView: View {
    let appearance: Appearance
    var size: CGFloat = 132

    public init(appearance: Appearance, size: CGFloat = 132) {
        self.appearance = appearance
        self.size = size
    }

    public var body: some View {
        let skin = Palette.skin[safe: appearance.skin] ?? Palette.skin[0]
        let hair = Palette.hair[safe: appearance.hair] ?? Palette.hair[0]
        let outfit = Palette.outfit[safe: appearance.outfit] ?? Palette.outfit[0]
        let u = size / 132
        let long = appearance.hairStyle == .long
        let base = Color.clear

        ZStack {
            // body
            UnevenRoundedRectangle(topLeadingRadius: 44 * u, bottomLeadingRadius: 20 * u, bottomTrailingRadius: 20 * u, topTrailingRadius: 44 * u)
                .fill(LinearGradient(colors: [Color(hex: outfit), base.shaded(outfit, by: -18)], startPoint: .top, endPoint: .bottom))
                .frame(width: 86 * u, height: 56 * u)
                .position(x: size / 2, y: size - 28 * u)

            // long hair behind the head
            if long {
                UnevenRoundedRectangle(topLeadingRadius: 46 * u, bottomLeadingRadius: 36 * u, bottomTrailingRadius: 36 * u, topTrailingRadius: 46 * u)
                    .fill(Color(hex: hair))
                    .frame(width: 92 * u, height: 96 * u)
                    .position(x: size / 2, y: 16 * u + 48 * u)
            }

            // head
            ZStack {
                Circle().fill(RadialGradient(
                    colors: [base.shaded(skin, by: 12), Color(hex: skin)],
                    center: UnitPoint(x: 0.38, y: 0.34), startRadius: 0, endRadius: 52 * u))
                Circle().fill(Color(hex: 0x3A2E28)).frame(width: 11 * u, height: 11 * u).position(x: 31.5 * u, y: 35.5 * u)
                Circle().fill(Color(hex: 0x3A2E28)).frame(width: 11 * u, height: 11 * u).position(x: 51.5 * u, y: 35.5 * u)
                Ellipse().fill(Color(red: 214 / 255, green: 110 / 255, blue: 120 / 255, opacity: 0.32))
                    .frame(width: 12 * u, height: 8 * u).position(x: 19 * u, y: 44 * u)
                Ellipse().fill(Color(red: 214 / 255, green: 110 / 255, blue: 120 / 255, opacity: 0.32))
                    .frame(width: 12 * u, height: 8 * u).position(x: 57 * u, y: 44 * u)
                Path { p in
                    p.addArc(center: CGPoint(x: 38 * u, y: 46 * u), radius: 10 * u, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
                }
                .stroke(base.shaded(skin, by: -42), style: StrokeStyle(lineWidth: 2.6 * u, lineCap: .round))
            }
            .frame(width: 76 * u, height: 76 * u)
            .position(x: size / 2, y: 18 * u + 38 * u)

            // front hair
            Group {
                if long {
                    UnevenRoundedRectangle(topLeadingRadius: 42 * u, bottomLeadingRadius: 10 * u, bottomTrailingRadius: 10 * u, topTrailingRadius: 42 * u)
                        .fill(Color(hex: hair))
                        .frame(width: 82 * u, height: 40 * u)
                        .position(x: size / 2, y: 14 * u + 20 * u)
                } else {
                    UnevenRoundedRectangle(topLeadingRadius: 42 * u, bottomLeadingRadius: 6 * u, bottomTrailingRadius: 6 * u, topTrailingRadius: 42 * u)
                        .fill(Color(hex: hair))
                        .frame(width: 82 * u, height: 27 * u)
                        .position(x: size / 2, y: 14 * u + 13.5 * u)
                }
            }
        }
        .frame(width: size, height: size)
        // The glow is a background: a layer bigger than the avatar must not shift the positioned shapes.
        .background {
            Circle()
                .fill(RadialGradient(colors: [Theme.accent.opacity(0.32), .clear], center: .center, startRadius: 0, endRadius: size * 0.6))
                .frame(width: size * 1.36, height: size * 1.36)
        }
        .accessibilityHidden(true)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
