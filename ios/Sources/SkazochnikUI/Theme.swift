import SwiftUI
import SkazochnikCore

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Lightens (positive) or darkens (negative) by adding `amount` (0...255) to every channel, like the prototype's `shade`.
    func shaded(_ hex: UInt32, by amount: Int) -> Color {
        func clamp(_ v: Int) -> Double { Double(max(0, min(255, v))) / 255 }
        return Color(
            .sRGB,
            red: clamp(Int((hex >> 16) & 0xFF) + amount),
            green: clamp(Int((hex >> 8) & 0xFF) + amount),
            blue: clamp(Int(hex & 0xFF) + amount)
        )
    }
}

/// Night palette and type from docs/design/prototype/styles.css (see docs/product/Design_System.md).
public enum Theme {
    public static let bg0 = Color(hex: 0x100C1F)
    public static let bg1 = Color(hex: 0x1A1430)
    public static let bg2 = Color(hex: 0x211A3C)
    public static let card = Color(hex: 0x221E3A, opacity: 0.55)
    public static let card2 = Color(hex: 0x2C264A, opacity: 0.72)
    public static let text = Color(hex: 0xF6EBDD)
    public static let text2 = Color(hex: 0xB7AFA4)
    public static let text3 = Color(hex: 0x8A82A3)
    public static let accent = Color(hex: 0xB8A7FF)
    public static let accentDeep = Color(hex: 0x8B6EDB)
    public static let accentSoft = Color(hex: 0xB8A7FF, opacity: 0.16)
    public static let gold = Color(hex: 0xE6A85C)
    public static let goldSoft = Color(hex: 0xE6A85C, opacity: 0.16)
    public static let border = Color(hex: 0xF6EBDD, opacity: 0.10)
    public static let borderStrong = Color(hex: 0xF6EBDD, opacity: 0.18)

    // The design uses Lora (serif) and Onest (sans). Until the font files are bundled the system
    // serif and sans stand in for them; switch these two functions to `.custom` once they are.
    public static func serif(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    public static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

/// Palettes the profile editor offers; `Appearance` stores indexes into these.
public enum Palette {
    public static let skin: [UInt32] = [0xF3D3B8, 0xE7B894, 0xCF9A6E, 0xA87148, 0x7A5333]
    public static let hair: [UInt32] = [0x3A2A1C, 0x6B4423, 0xA8743C, 0xD9A441, 0xE8E0D4, 0x2A2730]
    public static let outfit: [UInt32] = [0x8B6EDB, 0x4F9D8A, 0xD98A6B, 0x5C7BD9, 0xC76AA8]
}

public struct WorldInfo: Identifiable, Sendable {
    public let id: WorldID
    public let name: String
    let from: UInt32
    let to: UInt32

    public var gradient: LinearGradient {
        LinearGradient(colors: [Color(hex: from), Color(hex: to)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public static let all: [WorldInfo] = [
        WorldInfo(id: .forest, name: "Волшебный лес", from: 0x1D3A2E, to: 0x16433A),
        WorldInfo(id: .ocean, name: "Подводный мир", from: 0x163A5C, to: 0x1A5A6E),
        WorldInfo(id: .space, name: "Далёкий космос", from: 0x241B52, to: 0x3A2150),
        WorldInfo(id: .castle, name: "Замки и рыцари", from: 0x3A2D22, to: 0x5C3F2F),
        WorldInfo(id: .clouds, name: "Облачное королевство", from: 0x2A3560, to: 0x46538C),
        WorldInfo(id: .jungle, name: "Джунгли", from: 0x274A22, to: 0x3F5C2F),
    ]

    public static func named(_ id: WorldID) -> WorldInfo {
        all.first { $0.id == id } ?? all[0]
    }
}

public enum Interests {
    public static let all = [
        "Динозавры", "Космос", "Животные", "Лошади", "Машинки", "Море",
        "Принцессы", "Роботы", "Волшебство", "Пираты", "Феи", "Рыцари",
        "Природа", "Музыка", "Спорт", "Драконы",
    ]
}

/// "год", "года" or "лет" for an age in years.
public func ageWord(_ n: Int) -> String {
    let m10 = n % 10
    let m100 = n % 100
    if m10 == 1 && m100 != 11 { return "год" }
    if (2...4).contains(m10) && !(12...14).contains(m100) { return "года" }
    return "лет"
}
