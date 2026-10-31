import SwiftUI
import SkazochnikCore

/// The child a story is about, as the story screens need it.
public struct HeroInfo: Equatable, Sendable {
    public var name: String
    public var age: Int
    public var appearance: Appearance

    public init(name: String, age: Int, appearance: Appearance = Appearance()) {
        self.name = name
        self.age = age
        self.appearance = appearance
    }

    public init(profile: ChildProfile) {
        self.init(name: profile.name, age: profile.age, appearance: profile.appearance ?? Appearance())
    }
}

/// Night landscape of the book cover and inline scenes.
struct NightLandscape: View {
    var moonSize: CGFloat = 56

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                LinearGradient(colors: [Color(hex: 0x2A1D52), Color(hex: 0x1C2752), Color(hex: 0x14315C)], startPoint: .top, endPoint: .bottom)
                StarField(count: 28, seed: 7, animated: false)
                MoonIcon(size: moonSize).position(x: w - 30 - moonSize / 2, y: 26 + moonSize / 2)
                hill(width: w * 0.7, height: h * 0.34, from: 0x243A6E, to: 0x1A2C54).position(x: w * 0.23, y: h - h * 0.12)
                hill(width: w * 0.8, height: h * 0.4, from: 0x1C2C5A, to: 0x16234A).position(x: w * 0.76, y: h - h * 0.08)
                hill(width: w * 0.74, height: h * 0.26, from: 0x16213F, to: 0x10182F).position(x: w * 0.5, y: h - h * 0.02)
            }
        }
    }

    private func hill(width: CGFloat, height: CGFloat, from: UInt32, to: UInt32) -> some View {
        Ellipse()
            .fill(LinearGradient(colors: [Color(hex: from), Color(hex: to)], startPoint: .top, endPoint: .bottom))
            .frame(width: width, height: height * 2)
            .frame(width: width, height: height, alignment: .top)
            .clipped()
    }
}

/// Cover of a freshly created story: night scene with the hero standing on the front hill.
struct BookCover: View {
    let hero: HeroInfo
    var kicker = "Сказка на ночь"
    var height: CGFloat = 330
    var heroSize: CGFloat = 132
    /// The generated illustration; the night scene stands in until it loads (or if it cannot be shown).
    var imageURL: URL?

    var body: some View {
        ZStack(alignment: .top) {
            NightLandscape()
            HeroAvatarView(appearance: hero.appearance, size: heroSize)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 30)
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                            .overlay(alignment: .top) {
                                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                                    .frame(height: 90)
                            }
                    }
                }
            }
            Text(kicker)
                .kicker()
                .foregroundStyle(Theme.gold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.text.opacity(0.1)))
        .shadow(color: .black.opacity(0.45), radius: 26, y: 18)
    }
}
