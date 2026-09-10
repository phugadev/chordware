import ChordwareCore
import CoreGraphics

/// Where every key sits, as pure geometry.
///
/// Extracted from the drawing code so the mapping from MIDI note to on-screen
/// key can be tested. A keyboard that highlights the wrong key is worse than
/// no keyboard at all, and it is not something you can eyeball reliably.
public struct PianoLayout: Equatable, Sendable {
    public struct Key: Equatable, Sendable {
        public let note: Int
        public let isBlack: Bool
        public let rect: CGRect
    }

    public let lowNote: Int
    public let octaves: Int
    public let size: CGSize
    public let whiteCount: Int
    public let keys: [Key]

    /// Semitone offsets of the white keys within an octave.
    public static let whiteOffsets = [0, 2, 4, 5, 7, 9, 11]

    /// Black keys, as (semitone offset, which white-key boundary it straddles).
    ///
    /// A black key is centred on the *boundary* between two white keys: C# sits
    /// on the C/D boundary, which is one white key from the octave's start; F#
    /// sits on the F/G boundary, four white keys along. The gaps at 3 and 7 are
    /// the E/F and B/C boundaries, which have no black key — that is what gives
    /// a keyboard its groups of two and three.
    public static let blackOffsets: [(semitone: Int, boundary: Int)] = [
        (1, 1), (3, 2), (6, 4), (8, 5), (10, 6),
    ]

    public init(lowNote: Int, octaves: Int, size: CGSize) {
        self.lowNote = lowNote
        self.octaves = octaves
        self.size = size
        whiteCount = octaves * 7 + 1

        let whiteWidth = size.width / CGFloat(whiteCount)
        let blackWidth = whiteWidth * 0.58
        let blackHeight = size.height * 0.62

        var keys: [Key] = []
        for index in 0..<whiteCount {
            let octave = index / 7
            let degree = index % 7
            let note = lowNote + octave * 12 + Self.whiteOffsets[degree]
            keys.append(Key(
                note: note,
                isBlack: false,
                rect: CGRect(x: CGFloat(index) * whiteWidth, y: 0,
                             width: whiteWidth, height: size.height)
            ))
        }
        for octave in 0..<octaves {
            for black in Self.blackOffsets {
                let note = lowNote + octave * 12 + black.semitone
                let centre = CGFloat(octave * 7 + black.boundary) * whiteWidth
                keys.append(Key(
                    note: note,
                    isBlack: true,
                    rect: CGRect(x: centre - blackWidth / 2, y: 0,
                                 width: blackWidth, height: blackHeight)
                ))
            }
        }
        self.keys = keys
    }

    public var whiteKeys: [Key] { keys.filter { !$0.isBlack } }
    public var blackKeys: [Key] { keys.filter(\.isBlack) }
    public var noteRange: ClosedRange<Int> { lowNote...(lowNote + octaves * 12) }

    public func key(for note: Int) -> Key? { keys.first { $0.note == note } }
}
