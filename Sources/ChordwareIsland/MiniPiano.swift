import ChordwareCore
import SwiftUI

/// A compact keyboard showing what is being held. Drawn with Canvas rather than
/// stacked views so the black keys land on exact fractional positions at any
/// width without accumulating layout rounding error.
public struct MiniPiano: View {
    public var heldNotes: [Int]
    /// Notes belonging to the current scale; everything else is dimmed.
    public var scaleNotes: Set<PitchClass>
    public var lowNote: Int
    public var octaves: Int

    /// Range defaults to whatever covers the held notes. A fixed two octaves
    /// silently drops anything above it, which hides exactly the extensions
    /// that make a voicing interesting.
    public init(heldNotes: [Int], scaleNotes: Set<PitchClass> = [],
                lowNote: Int? = nil, octaves: Int? = nil) {
        self.heldNotes = heldNotes
        self.scaleNotes = scaleNotes

        let lowest = heldNotes.min() ?? 48
        let highest = heldNotes.max() ?? 71
        let floorC = (lowest / 12) * 12
        let ceilC = ((highest / 12) + 1) * 12
        self.lowNote = lowNote ?? floorC
        self.octaves = octaves ?? min(5, max(2, (ceilC - floorC) / 12))
    }

    private static let whiteOffsets = [0, 2, 4, 5, 7, 9, 11]
    /// Black keys by semitone, positioned in white-key units from the octave's
    /// C. A black key sits centred on the *boundary* between two white keys, so
    /// C# is at 1.0 (the C/D boundary) and F# at 4.0 (the F/G boundary). This is
    /// what produces the familiar groups of two and three.
    private static let blackOffsets: [(semitone: Int, position: Double)] = [
        (1, 1.0), (3, 2.0), (6, 4.0), (8, 5.0), (10, 6.0),
    ]

    private var whiteCount: Int { octaves * 7 + 1 }

    public var body: some View {
        Canvas { context, size in
            let whiteWidth = size.width / CGFloat(whiteCount)
            let blackWidth = whiteWidth * 0.58
            let blackHeight = size.height * 0.62
            let held = Set(heldNotes)
            // With no key established, nothing is "out of key", so draw a
            // normal keyboard rather than dimming every note.
            let hasScale = !scaleNotes.isEmpty

            for index in 0..<whiteCount {
                let octave = index / 7, degree = index % 7
                let note = lowNote + octave * 12 + Self.whiteOffsets[degree]
                let rect = CGRect(x: CGFloat(index) * whiteWidth + 0.5, y: 0,
                                  width: whiteWidth - 1, height: size.height)
                let path = Path(roundedRect: rect, cornerRadius: 2)
                if held.contains(note) {
                    context.fill(path, with: .color(IslandTheme.accent))
                } else if !hasScale || scaleNotes.contains(PitchClass(note)) {
                    context.fill(path, with: .color(Color.white.opacity(0.82)))
                } else {
                    // Out of key: present, but clearly not part of the picture.
                    context.fill(path, with: .color(Color.white.opacity(0.30)))
                }
            }

            for octave in 0..<octaves {
                for black in Self.blackOffsets {
                    let note = lowNote + octave * 12 + black.semitone
                    let x = (CGFloat(octave * 7) + CGFloat(black.position)) * whiteWidth
                        + whiteWidth - blackWidth / 2
                    let rect = CGRect(x: x, y: 0, width: blackWidth, height: blackHeight)
                    let path = Path(roundedRect: rect, cornerRadius: 2)
                    if held.contains(note) {
                        context.fill(path, with: .color(IslandTheme.accent))
                    } else if !hasScale || scaleNotes.contains(PitchClass(note)) {
                        context.fill(path, with: .color(Color(white: 0.13)))
                    } else {
                        context.fill(path, with: .color(Color(white: 0.13)))
                        context.fill(path, with: .color(Color.black.opacity(0.55)))
                    }
                    context.stroke(path, with: .color(.black), lineWidth: 1)
                }
            }
        }
    }
}
