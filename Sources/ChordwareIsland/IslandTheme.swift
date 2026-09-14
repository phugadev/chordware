import ChordwareCore
import SwiftUI

/// Always dark, in both system themes. The window is a black readout and a
/// keyboard: the keys have to be the brightest thing on screen, and what you
/// are holding down has to be the only colour on it.
public enum IslandTheme {
    /// The window's ground. Not the chord panel -- that is pure black.
    public static let background = Color(red: 0.106, green: 0.110, blue: 0.118)
    /// The chord display. Actually black, so the panel reads as a readout
    /// rather than as another shade of window, and so an empty one is plainly
    /// empty.
    public static let panel = Color.black
    /// The keybed the keys sit in.
    public static let surfaceHigh = Color(red: 0.145, green: 0.149, blue: 0.160)

    public static let primary = Color.white
    public static let secondary = Color.white.opacity(0.60)
    public static let tertiary = Color.white.opacity(0.34)

    /// One colour for everything that is being played: every held key, and the
    /// chord name above them.
    ///
    /// There were four here, one per chord tone, and they were the wrong answer
    /// to a real question. Colouring by function means learning a legend before
    /// the display tells you anything, and it makes a thirteenth chord look
    /// like a paint chart. One vivid colour says the only thing the keyboard
    /// has to say at a glance -- *these* are down -- and the chord name in the
    /// same colour ties the two halves of the window together without a rule
    /// between them.
    public static let played = Color(red: 0.161, green: 0.639, blue: 1.0)

    public static func chordFont(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    public static func labelFont(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

}
