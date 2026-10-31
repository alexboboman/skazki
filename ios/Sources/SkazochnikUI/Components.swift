import SwiftUI

// MARK: Background

/// Night gradient with aurora glow and twinkling stars.
public struct NightBackground: View {
    var starCount = 40
    var seed: UInt64 = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(starCount: Int = 40, seed: UInt64 = 1) {
        self.starCount = starCount
        self.seed = seed
    }

    public var body: some View {
        ZStack {
            RadialGradient(
                colors: [Theme.bg2, Theme.bg1, Theme.bg0],
                center: UnitPoint(x: 0.5, y: -0.1),
                startRadius: 0,
                endRadius: 900
            )
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0x8B6EDB, opacity: 0.55), .clear], center: .center, startRadius: 0, endRadius: 170))
                .frame(width: 340, height: 340)
                .blur(radius: 40)
                .offset(x: -150, y: -330)
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0x3C5AA0, opacity: 0.5), .clear], center: .center, startRadius: 0, endRadius: 150))
                .frame(width: 300, height: 300)
                .blur(radius: 40)
                .offset(x: 150, y: 330)
            StarField(count: starCount, seed: seed, animated: !reduceMotion)
        }
        .ignoresSafeArea()
    }
}

struct StarField: View {
    struct Star {
        var x: Double, y: Double, size: Double, phase: Double, speed: Double, low: Double, high: Double
    }

    let stars: [Star]
    let animated: Bool

    init(count: Int, seed: UInt64, animated: Bool) {
        var rng = SeededGenerator(seed: seed)
        stars = (0..<count).map { _ in
            Star(
                x: Double.random(in: 0...1, using: &rng),
                y: Double.random(in: 0...1, using: &rng),
                size: Double.random(in: 1...2.6, using: &rng),
                phase: Double.random(in: 0...6.28, using: &rng),
                speed: Double.random(in: 0.6...1.6, using: &rng),
                low: Double.random(in: 0.1...0.3, using: &rng),
                high: Double.random(in: 0.6...1, using: &rng)
            )
        }
        self.animated = animated
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !animated)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                for star in stars {
                    let wave = animated ? (sin(t * star.speed + star.phase) + 1) / 2 : 0.5
                    let opacity = star.low + (star.high - star.low) * wave
                    let rect = CGRect(x: star.x * size.width, y: star.y * size.height, width: star.size, height: star.size)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Small deterministic generator so each screen keeps its own star pattern between launches.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed &* 6364136223846793005 &+ 1442695040888963407
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: Text styles

public extension View {
    func kicker() -> some View {
        font(Theme.sans(13, weight: .semibold))
            .tracking(2.3)
            .textCase(.uppercase)
            .foregroundStyle(Theme.accent)
    }

    func display(_ size: CGFloat = 33) -> some View {
        font(Theme.serif(size))
            .foregroundStyle(Theme.text)
            .lineSpacing(2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    func titleStyle(_ size: CGFloat = 27) -> some View {
        font(Theme.serif(size)).foregroundStyle(Theme.text).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
    }

    func bodyStyle(_ size: CGFloat = 16.5) -> some View {
        font(Theme.sans(size)).foregroundStyle(Theme.text2).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
    }

    func captionStyle(_ size: CGFloat = 13.5) -> some View {
        font(Theme.sans(size)).foregroundStyle(Theme.text3)
    }
}

// MARK: Buttons

public struct PillButtonStyle: ButtonStyle {
    public enum Kind { case primary, gold, ghost }

    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    public init(_ kind: Kind = .primary) {
        self.kind = kind
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.sans(17, weight: kind == .ghost ? .medium : .semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: kind == .ghost ? 50 : 56)
            .background(background)
            .clipShape(Capsule())
            .shadow(color: shadow, radius: 14, y: 8)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.972 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: Color(hex: 0x1A1330)
        case .gold: Color(hex: 0x2B1C0C)
        case .ghost: Theme.text2
        }
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .primary:
            LinearGradient(colors: [Color(hex: 0xD9CCFF), Theme.accent, Theme.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .gold:
            LinearGradient(colors: [Color(hex: 0xF7D9A8), Theme.gold, Color(hex: 0xD2873F)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .ghost:
            Color.clear
        }
    }

    private var shadow: Color {
        guard isEnabled else { return .clear }
        switch kind {
        case .primary: return Theme.accentDeep.opacity(0.5)
        case .gold: return Theme.gold.opacity(0.45)
        case .ghost: return .clear
        }
    }
}

public extension ButtonStyle where Self == PillButtonStyle {
    static var primaryPill: PillButtonStyle { PillButtonStyle(.primary) }
    static var goldPill: PillButtonStyle { PillButtonStyle(.gold) }
    static var ghostPill: PillButtonStyle { PillButtonStyle(.ghost) }
}

// MARK: Selectable surfaces

public struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    public init(_ title: String, selected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.selected = selected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.sans(15.5, weight: .medium))
                .foregroundStyle(selected ? Theme.text : Theme.text2)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(selected ? Theme.accentSoft : Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Theme.accent : Theme.border, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

public extension View {
    /// Rounded card or tile surface with the selected state of the design.
    func tileSurface(selected: Bool = false, radius: CGFloat = 22) -> some View {
        background(selected ? Theme.accentSoft : Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Theme.border, lineWidth: selected ? 1.5 : 1)
            )
    }

    func glassCard(radius: CGFloat = 26) -> some View {
        background(.ultraThinMaterial.opacity(0.35), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

public struct CircleIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    public init(systemName: String, label: String, action: @escaping () -> Void) {
        self.systemName = systemName
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 42, height: 42)
                .background(Theme.card, in: Circle())
                .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

public struct ProgressSegments: View {
    let step: Int
    let total: Int

    public init(step: Int, total: Int) {
        self.step = step
        self.total = total
    }

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= step
                        ? AnyShapeStyle(LinearGradient(colors: [Theme.accent, Theme.gold], startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(Theme.text.opacity(0.14)))
                    .frame(height: 4)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Шаг \(step + 1) из \(total)")
    }
}

// MARK: Shapes

public struct MoonIcon: View {
    var size: CGFloat = 96

    public init(size: CGFloat = 96) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Theme.accent.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: size * 0.8))
                .frame(width: size * 1.6, height: size * 1.6)
            Circle()
                .fill(LinearGradient(colors: [Color(hex: 0xFFF3D6), Color(hex: 0xF0C987)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .mask(
                    ZStack {
                        Rectangle()
                        Circle().frame(width: size * 0.82, height: size * 0.82).offset(x: size * 0.28, y: -size * 0.14).blendMode(.destinationOut)
                    }
                    .compositingGroup()
                )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let k = r * 0.22
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + k, y: c.y - k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - k, y: c.y - k))
        return p
    }
}

public struct Sparkle: View {
    var size: CGFloat = 18
    var color: Color = Theme.accent

    public init(size: CGFloat = 18, color: Color = Theme.accent) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        SparkleShape().fill(color).frame(width: size, height: size).accessibilityHidden(true)
    }
}

// MARK: Snapshots

private struct SnapshotModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// ImageRenderer cannot draw ScrollView content, so snapshot tests ask scrolling containers to lay out flat.
    var snapshotMode: Bool {
        get { self[SnapshotModeKey.self] }
        set { self[SnapshotModeKey.self] = newValue }
    }
}

/// ScrollView that lays out flat when `snapshotMode` is on.
struct AdaptiveScroll<Content: View>: View {
    var axis: Axis.Set = .vertical
    @ViewBuilder var content: () -> Content
    @Environment(\.snapshotMode) private var snapshot

    var body: some View {
        if snapshot {
            if axis == .vertical {
                content().frame(maxHeight: .infinity, alignment: .top)
            } else {
                ClipToProposedWidth { content() }.clipped()
            }
        } else {
            ScrollView(axis) { content() }.scrollIndicators(.hidden)
        }
    }
}

/// Lays its child out at its natural width but reports only the proposed width, like a horizontal scroll view would.
struct ClipToProposedWidth: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let child = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: proposal.width ?? child.width, height: child.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: .unspecified)
    }
}
