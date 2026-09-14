import ChordwareCore
import SwiftUI

/// Always dark, in both system themes. The window is a black readout and a
/// keyboard: the keys have to be the brightest thing on screen, and what you
/// are holding down has to be the only colour on it.
public enum Theme {
    /// The window's ground. Not the chord panel -- that is pure black.
    public static let background = Color(red: 0.106, green: 0.110, blue: 0.118)
    /// The chord display. Actually black, so the panel reads as a readout
    /// rather than as another shade of window, and so an empty one is plainly
    /// empty.
    public static let panel = Color.black
    /// The keybed the keys sit in.
    public static let surfaceHigh = Color(red: 0.145, green: 0.149, blue: 0.160)

    public static let secondary = Color.white.opacity(0.60)
    public static let tertiary = Color.white.opacity(0.34)

    /// The three colours the app has anything to say with.
    ///
    /// Passed down rather than read from a global, so alternatives can be
    /// rendered side by side without the shipping window changing underneath.
    public struct Palette: Sendable {
        /// The chord you are playing, in the readout.
        public let chord: Color
        /// White keys under your fingers. Darker than ivory, or it does not
        /// read as pressed.
        public let whiteKey: Color
        /// Black keys under your fingers. Lighter than the keys either side of
        /// it, for the same reason in the other direction.
        public let blackKey: Color
        /// Drawn on a held key. Follows its key's lightness, so both always
        /// read: white on the dark one, near-black on the light one.
        public let whiteKeyLabel: Color
        public let blackKeyLabel: Color
        /// Input is live.
        public let live: Color

        public init(chord: Color, whiteKey: Color, blackKey: Color,
                    whiteKeyLabel: Color = .white,
                    blackKeyLabel: Color = Color(white: 0.08),
                    live: Color) {
            self.chord = chord
            self.whiteKey = whiteKey
            self.blackKey = blackKey
            self.whiteKeyLabel = whiteKeyLabel
            self.blackKeyLabel = blackKeyLabel
            self.live = live
        }
    }

    /// Two hues, three jobs.
    ///
    /// The keyboard is one hue at two lightnesses, because "a key is down" is
    /// one fact and "which kind of key" is a second one -- hue says the first,
    /// lightness says the second, and the lightness is picked for the key it
    /// lands on rather than for taste. The chord is the complementary warm,
    /// because it is the one thing on screen that is not a key.
    ///
    /// Amber, green and violet before this was three unrelated hues doing three
    /// unrelated things, which is a palette by accident rather than on purpose.
    public static let emerald = Palette(
        chord: Color(red: 1.00, green: 0.651, blue: 0.169),
        whiteKey: Color(red: 0.055, green: 0.624, blue: 0.431),
        blackKey: Color(red: 0.431, green: 0.906, blue: 0.718),
        live: Color(red: 0.055, green: 0.624, blue: 0.431))

    /// Two hues rather than two lightnesses of one.
    ///
    /// Emerald's mint black keys were the right idea badly executed: a pale
    /// tint of the same hue is the only way to stay lighter than a black key,
    /// and pale next to an ivory white key is barely there. Put a Bb in a
    /// Bbmaj7 -- D, F, A, Bb, three white keys and one black -- and the one you
    /// most need to see is the faintest thing on the board.
    ///
    /// Two saturated hues instead, one per kind of key, both dark enough to
    /// carry a white label and each unmistakable against what it sits on:
    /// violet is clearly darker than ivory, pink is clearly brighter than a
    /// black key.
    public static let orchid = Palette(
        chord: Color(red: 1.00, green: 0.651, blue: 0.169),
        whiteKey: Color(red: 0.443, green: 0.243, blue: 0.882),
        blackKey: Color(red: 0.937, green: 0.286, blue: 0.612),
        blackKeyLabel: .white,
        live: Color(red: 0.443, green: 0.243, blue: 0.882))

    /// Cooler, and further from anything else that looks like this.
    public static let indigo = Palette(
        chord: Color(red: 1.00, green: 0.667, blue: 0.231),
        whiteKey: Color(red: 0.357, green: 0.294, blue: 0.839),
        blackKey: Color(red: 0.663, green: 0.612, blue: 1.00),
        live: Color(red: 0.357, green: 0.294, blue: 0.839))

    /// Warm keys, cool chord: the same idea with the temperatures swapped.
    public static let coral = Palette(
        chord: Color(red: 0.298, green: 0.816, blue: 0.855),
        whiteKey: Color(red: 0.847, green: 0.286, blue: 0.286),
        blackKey: Color(red: 1.00, green: 0.647, blue: 0.600),
        live: Color(red: 0.847, green: 0.286, blue: 0.286))

    public static let standard = orchid


}
