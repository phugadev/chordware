import ChordwareCore
import SwiftUI

/// The island is always dark, in both system themes, because on a notched Mac
/// it has to blend into physically black hardware. The pill on a non-notched
/// screen keeps the same palette so the two read as one product.
public enum IslandTheme {
    public static let background = Color.black
    public static let primary = Color.white
    public static let secondary = Color.white.opacity(0.62)
    public static let tertiary = Color.white.opacity(0.34)
    public static let hairline = Color.white.opacity(0.12)

    public static let accent = Color(red: 0.42, green: 0.78, blue: 1.0)
    /// Belongs to the key.
    public static let diatonic = Color(red: 0.55, green: 0.85, blue: 0.72)
    /// Borrowed, altered or otherwise from outside it.
    public static let chromatic = Color(red: 1.0, green: 0.78, blue: 0.42)

    /// Held keys are coloured by what the note is doing in the chord. Four
    /// colours is the most that stays readable at a glance; beyond that it is
    /// decoration rather than information.
    public static func roleColor(_ role: ChordToneRole?) -> Color {
        switch role {
        case .root: return Color(red: 1.00, green: 0.72, blue: 0.35)      // the anchor
        case .third: return Color(red: 0.47, green: 0.87, blue: 0.66)     // major or minor
        case .fifth: return accent
        case .seventh, .tension: return Color(red: 0.79, green: 0.64, blue: 1.00)
        case nil: return accent
        }
    }

    /// Legend entries, one per distinct colour. The seventh and the tensions
    /// share a colour on purpose -- five is past what stays readable -- so they
    /// must share a swatch too rather than appearing twice.
    public static let roleLegend: [(label: String, color: Color)] = [
        ("root", roleColor(.root)),
        ("third", roleColor(.third)),
        ("fifth", roleColor(.fifth)),
        ("7th \u{0026} tensions", roleColor(.seventh)),
    ]

    public static func chordFont(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    public static func labelFont(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

    public static let spring = Animation.spring(response: 0.38, dampingFraction: 0.78)

    /// Shared by the window resize and the content, so the two cannot drift.
    ///
    /// AppKit picks its own duration for an animated setFrame, scaled to how
    /// much the window changed size. Left alone it runs on a different clock
    /// and a different curve from the SwiftUI animation inside it, and the
    /// transition reads as two things happening near each other rather than one
    /// thing moving.
    public static let modeTransitionDuration: Double = 0.30
    public static let modeTransition = Animation.easeInOut(duration: modeTransitionDuration)
    public static let quickSpring = Animation.spring(response: 0.26, dampingFraction: 0.82)
}
