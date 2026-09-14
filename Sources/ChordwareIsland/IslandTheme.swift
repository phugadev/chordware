import ChordwareCore
import SwiftUI

/// Always dark, in both system themes. The window is mostly a piano, and a
/// piano is a dark object with bright keys: invert that and the keys stop being
/// the brightest thing on screen, which is the one rule the whole layout rests
/// on.
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
    /// Recessed, for the well the chord sits in.
    ///
    /// Drawn as a gradient down to `background` rather than as a flat band: a
    /// flat one differs from the ground by too little to read as a recess and
    /// by just enough to leave a visible seam across the window.
    public static let well = Color(red: 0.019, green: 0.022, blue: 0.028)

    public static let primary = Color.white
    public static let secondary = Color.white.opacity(0.66)
    public static let tertiary = Color.white.opacity(0.38)
    public static let hairline = Color.white.opacity(0.09)
    /// The lit top edge of a raised surface: one pixel of light so a card has
    /// a top rather than just an outline.
    public static let edgeLight = Color.white.opacity(0.07)

    /// Also the fifth, so a keyboard with role colours off still reads as
    /// pressed rather than as highlighted.
    public static let accent = Color(red: 0.11, green: 0.49, blue: 0.90)
    /// Belongs to the key.
    public static let diatonic = Color(red: 0.55, green: 0.85, blue: 0.72)
    /// Borrowed, altered or otherwise from outside it.
    public static let chromatic = Color(red: 1.0, green: 0.78, blue: 0.42)

    /// Held keys are coloured by what the note is doing in the chord. Four
    /// colours is the most that stays readable at a glance; beyond that it is
    /// decoration rather than information.
    ///
    /// Saturated and dark, not pastel, and the same colour on a white key as on
    /// a black one. There were two palettes here, a pale set for white keys and
    /// a deep set for black ones, and both were wrong. A tint only reads as a
    /// tint when there is something lighter beside it for it to be a tint of; a
    /// pale orange key surrounded by white keys reads as a key that failed to
    /// draw. What makes a white key look *pressed* is that it went darker than
    /// its neighbours, which means the colour has to be darker than ivory --
    /// and a colour dark enough for that is also bright enough to read against
    /// a black key. One palette, one meaning per hue, wherever it lands.
    public static func roleColor(_ role: ChordToneRole?) -> Color {
        switch role {
        case .root: return Color(red: 0.94, green: 0.53, blue: 0.07)      // the anchor
        case .third: return Color(red: 0.07, green: 0.64, blue: 0.41)     // major or minor
        case .fifth: return accent
        case .seventh, .tension: return Color(red: 0.49, green: 0.28, blue: 0.89)
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
