import ChordwareCore
import SwiftUI

/// The island is always dark, in both system themes, because on a notched Mac
/// it has to blend into physically black hardware. The pill on a non-notched
/// screen keeps the same palette so the two read as one product.
public enum IslandTheme {
    /// The ground. Not pure black: a window of #000 with #FFF text on it has
    /// no depth to build on, because every surface laid over it can only go
    /// lighter and there is nowhere to go darker. A hair of blue keeps it from
    /// reading as a dead screen.
    public static let background = Color(red: 0.043, green: 0.047, blue: 0.055)
    /// Raised: the panel behind the keyboard and behind the detail rows.
    public static let surface = Color(red: 0.075, green: 0.081, blue: 0.094)
    /// Raised further, for the keybed the keys sit in.
    public static let surfaceHigh = Color(red: 0.105, green: 0.112, blue: 0.128)
    /// Recessed, for the well under the header.
    public static let well = Color(red: 0.028, green: 0.031, blue: 0.038)

    public static let primary = Color.white
    public static let secondary = Color.white.opacity(0.66)
    public static let tertiary = Color.white.opacity(0.38)
    public static let hairline = Color.white.opacity(0.09)
    /// The lit top edge of a raised surface: one pixel of light so a card has
    /// a top rather than just an outline.
    public static let edgeLight = Color.white.opacity(0.07)

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

    /// The same four roles, for a key that is itself dark.
    ///
    /// The pastels above are tints meant to sit on white. Put one on a black
    /// key, between two more black keys, and it reads as washed out rather than
    /// as pressed: there is nothing lighter around it for it to be a tint of.
    /// Same hue, more saturation, less brightness.
    public static func roleColorOnBlack(_ role: ChordToneRole?) -> Color {
        switch role {
        case .root: return Color(red: 0.93, green: 0.55, blue: 0.10)
        case .third: return Color(red: 0.20, green: 0.72, blue: 0.47)
        case .fifth: return Color(red: 0.13, green: 0.56, blue: 0.90)
        case .seventh, .tension: return Color(red: 0.58, green: 0.36, blue: 0.95)
        case nil: return Color(red: 0.13, green: 0.56, blue: 0.90)
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
