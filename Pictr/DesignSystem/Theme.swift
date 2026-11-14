import SwiftUI
import UIKit

/// acker design tokens for Pictr. Dark only. Red is a graphic colour: it never
/// colours text (3.2:1 on the base). Blue never carries meaning.
enum Theme {
    enum Palette {
        // Red and black. Measured: textPrimary 17.3:1 and textSecondary 8.3:1 on bgBase,
        // 7.8:1 on surface. Red is graphics only (3.6:1 on bgBase); white on red is 5.4:1.
        static let bgBase = Color(hex: 0x0B0B0B)
        static let bgDeep = Color(hex: 0x000000)
        static let surface = Color(hex: 0x141414)
        static let surfaceRaised = Color(hex: 0x1C1C1C)
        static let border = Color(hex: 0x262626)
        static let borderStrong = Color(hex: 0x333333)
        static let textPrimary = Color(hex: 0xF0F0F0)
        static let textSecondary = Color(hex: 0xA8A8A8)
        static let textMuted = Color(hex: 0x666666)     // 3.4:1: disabled only
        static let accent = Color(hex: 0xC0392B)        // graphics only; white text on it is 5.4:1
        static let accentHover = Color(hex: 0xA93226)
        static let accentSubtle = Color(hex: 0x2A0E0B)
        static let accentMuted = Color(hex: 0x7B241C)
    }

    enum Space {
        static let x1: CGFloat = 4
        static let x2: CGFloat = 8
        static let x3: CGFloat = 12
        static let x4: CGFloat = 16
        static let x5: CGFloat = 20
        static let x6: CGFloat = 24
        static let x8: CGFloat = 32
        static let x10: CGFloat = 40
        static let x12: CGFloat = 48
    }

    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        /// iOS deviation: the photo card is a large container under Liquid Glass chrome.
        static let card: CGFloat = 28
        /// Liquid Glass panels and grouped rows.
        static let glass: CGFloat = 24
    }

    enum Motion {
        static let fast = Animation.easeOut(duration: 0.1)
        static let base = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.2)
        static let slow = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.35)
    }

    /// Geist for display, DM Sans for body. All scale with Dynamic Type.
    enum Typeface {
        static let hero = Font.custom("Geist-Bold", size: 44, relativeTo: .largeTitle)
        static let title = Font.custom("Geist-SemiBold", size: 28, relativeTo: .title)
        /// Page titles in the toolbar row; scales with Dynamic Type but less than hero.
        static let pageTitle = Font.custom("Geist-Bold", size: 32, relativeTo: .title)
        static let title3 = Font.custom("Geist-SemiBold", size: 20, relativeTo: .title3)
        static let headline = Font.custom("Geist-SemiBold", size: 17, relativeTo: .headline)
        static let number = Font.custom("Geist-Medium", size: 15, relativeTo: .subheadline).monospacedDigit()
        static let eyebrow = Font.custom("Geist-Medium", size: 12, relativeTo: .caption)
        static let body = Font.custom("DMSans-9ptRegular_Regular", size: 16, relativeTo: .body)
        static let bodyMedium = Font.custom("DMSans-9ptRegular_Medium", size: 16, relativeTo: .body)
        static let callout = Font.custom("DMSans-9ptRegular_Regular", size: 15, relativeTo: .callout)
        static let caption = Font.custom("DMSans-9ptRegular_Regular", size: 13, relativeTo: .caption)
        static let captionMedium = Font.custom("DMSans-9ptRegular_Medium", size: 13, relativeTo: .caption)
    }

    /// Navigation bar titles in Geist. Call once at launch.
    @MainActor
    static func applyAppearance() {
        let large = UIFontMetrics(forTextStyle: .largeTitle)
            .scaledFont(for: UIFont(name: "Geist-Bold", size: 34) ?? .preferredFont(forTextStyle: .largeTitle))
        let inline = UIFontMetrics(forTextStyle: .headline)
            .scaledFont(for: UIFont(name: "Geist-SemiBold", size: 17) ?? .preferredFont(forTextStyle: .headline))
        let primary = UIColor(red: 0xF0 / 255, green: 0xF0 / 255, blue: 0xF0 / 255, alpha: 1)
        let appearance = UINavigationBar.appearance()
        appearance.largeTitleTextAttributes = [.font: large, .foregroundColor: primary]
        appearance.titleTextAttributes = [.font: inline, .foregroundColor: primary]
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Small caps label above a headline.
struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Typeface.eyebrow)
            .kerning(1.0)
            .foregroundStyle(Theme.Palette.textSecondary)
    }
}

/// App background: a slow red-and-black mesh that drifts, so the glass above it
/// always has colour to bend. Still when Reduce Motion is on.
struct PictrBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                mesh(0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    mesh(context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func mesh(_ time: Double) -> some View {
        let t = Float(time.truncatingRemainder(dividingBy: 10_000) * 0.12)
        return MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5 + 0.15 * sin(t * 0.7), 0], [1, 0],
                [0, 0.45 + 0.1 * sin(t)], [0.5 + 0.18 * cos(t * 0.8), 0.5 + 0.14 * sin(t * 1.1)], [1, 0.55 + 0.1 * cos(t * 0.9)],
                [0, 1], [0.5 + 0.15 * cos(t * 0.6), 1], [1, 1],
            ],
            colors: [
                Color(hex: 0xC0392B), Color(hex: 0x5A1510), Color(hex: 0x0B0B0B),
                Color(hex: 0x140606), Color(hex: 0x4A100B), Color(hex: 0x7B241C),
                Color(hex: 0x000000), Color(hex: 0x1A0705), Color(hex: 0x2A0E0B),
            ],
            smoothsColors: true
        )
        .overlay(Theme.Palette.bgBase.opacity(0.35))
    }
}

/// Grouped-list row background: Liquid Glass with a breath of red.
struct GlassRow: View {
    var body: some View {
        Rectangle()
            .fill(.clear)
            .glassEffect(.regular.tint(Theme.Palette.accent.opacity(0.06)), in: Rectangle())
    }
}

/// Section title: a short red bar and small caps.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: Theme.Space.x2) {
            Capsule().fill(Theme.Palette.accent).frame(width: 3, height: 12)
            Text(text.uppercased())
                .font(Theme.Typeface.eyebrow)
                .kerning(1.0)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .textCase(nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Red rounded-square icon for rows, the way Settings marks its rows.
struct IconTile: View {
    let systemName: String
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [Theme.Palette.accent, Theme.Palette.accentMuted],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: size * 0.26)
            )
            .accessibilityHidden(true)
    }
}

/// Text label with a red icon tile, for form rows.
struct RowLabel: View {
    let title: String
    let systemImage: String
    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label { Text(title) } icon: { IconTile(systemName: systemImage) }
    }
}

/// Hairline that glows red along the top edge.
struct EmberStroke: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: radius)
                .stroke(LinearGradient(colors: [Theme.Palette.accent.opacity(0.55), Theme.Palette.border, Theme.Palette.border],
                                       startPoint: .top, endPoint: .bottom), lineWidth: 1)
        )
    }
}

/// A surface panel: acker card geometry.
struct Panel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Theme.Space.x4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(Theme.Palette.accent.opacity(0.08)),
                         in: RoundedRectangle(cornerRadius: Theme.Radius.glass, style: .continuous))
    }
}

extension View {
    /// Primary call to action: red Liquid Glass, white label.
    func primaryGlassButton() -> some View {
        self
            .font(Theme.Typeface.headline)
            .foregroundStyle(.white)
            .buttonStyle(.glassProminent)
            .tint(Theme.Palette.accent)
            .controlSize(.large)
    }

    /// Secondary action: clear Liquid Glass.
    func secondaryGlassButton() -> some View {
        self
            .font(Theme.Typeface.bodyMedium)
            .foregroundStyle(Theme.Palette.textPrimary)
            .buttonStyle(.glass)
            .controlSize(.large)
    }

    func emberStroke(radius: CGFloat = Theme.Radius.lg) -> some View {
        modifier(EmberStroke(radius: radius))
    }

    /// Lists and forms drawn on the red-and-black background with black rows.
    func pictrList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(PictrBackground())
            .listRowSeparatorTint(.white.opacity(0.08))
            .listSectionSpacing(Theme.Space.x5)
    }
}

/// Tiles and cards: sink slightly under the finger with a spring.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
