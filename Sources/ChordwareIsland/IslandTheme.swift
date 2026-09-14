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

    /// The chord you are playing, in the readout.
    ///
    /// Amber rather than cyan, because cyan on black over a keyboard is
    /// ChordWatch's face and this should not be mistaken for it.
    public static let chord = Color(red: 0.914, green: 0.510, blue: 0.055)

    /// White keys under your fingers.
    public static let playedWhite = Color(red: 0.122, green: 0.663, blue: 0.408)

    /// Black keys under your fingers.
    ///
    /// Its own colour, not a shade of the white keys'. A black key is narrow,
    /// half-height and sits between two white ones, so a pressed C# in the same
    /// colour as a pressed C reads as one wide smear rather than two notes --
    /// which is exactly the reading you need when you are checking whether you
    /// caught the sharp.
    public static let playedBlack = Color(red: 0.541, green: 0.361, blue: 0.965)

    /// Input is live. Shares the keyboard's green: both mean notes are arriving.
    public static let live = Color(red: 0.153, green: 0.784, blue: 0.478)

    public static func chordFont(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    public static func labelFont(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

}
