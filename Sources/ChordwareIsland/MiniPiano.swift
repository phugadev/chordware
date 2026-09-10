import ChordwareCore
import SwiftUI

/// A keyboard showing what is sounding.
///
/// Geometry comes from `PianoLayout` rather than being recomputed here. It used
/// to be duplicated, the two copies drifted, and every black key ended up drawn
/// one white key to the right — which put a black key on the E/F seam where
/// none belongs and shifted the groups of two and three that people actually
/// use to read a keyboard.
public struct MiniPiano: View {
    public var heldNotes: [Int]
    /// Notes belonging to the current scale; everything else is dimmed.
    public var scaleNotes: Set<PitchClass>
    public var lowNote: Int
    public var octaves: Int
    /// Label each C, so the octave you are looking at is unambiguous.
    public var showsOctaveLabels: Bool

    /// C2 to C6, which covers where chords are actually voiced.
    private static let defaultLow = 36
    private static let defaultHigh = 84

    /// The range is fixed by default, and only stretches for notes outside it.
    ///
    /// Sizing it to each voicing looks fine in a still and is horrible in
    /// motion: every chord change resizes the whole keyboard, so the eye has to
    /// re-find middle C constantly.
    public init(heldNotes: [Int], scaleNotes: Set<PitchClass> = [],
                lowNote: Int? = nil, octaves: Int? = nil,
                showsOctaveLabels: Bool = false) {
        self.heldNotes = heldNotes
        self.scaleNotes = scaleNotes
        self.showsOctaveLabels = showsOctaveLabels

        let lowest = min(heldNotes.min() ?? Self.defaultLow, Self.defaultLow)
        let highest = max(heldNotes.max() ?? Self.defaultHigh, Self.defaultHigh)
        let floorC = (lowest / 12) * 12
        let ceilC = ((highest + 11) / 12) * 12
        self.lowNote = lowNote ?? floorC
        self.octaves = octaves ?? max(1, (ceilC - floorC) / 12)
    }

    public var body: some View {
        Canvas { context, size in
            let layout = PianoLayout(lowNote: lowNote, octaves: octaves, size: size)
            let held = Set(heldNotes)
            // With no key established nothing is "out of key", so draw a normal
            // keyboard rather than dimming every note.
            let hasScale = !scaleNotes.isEmpty

            for key in layout.whiteKeys {
                // Inset so neighbouring keys read as separate.
                let rect = key.rect.insetBy(dx: 0.5, dy: 0)
                let path = Path(roundedRect: rect, cornerRadius: 2)
                if held.contains(key.note) {
                    context.fill(path, with: .color(IslandTheme.accent))
                } else if !hasScale || scaleNotes.contains(PitchClass(key.note)) {
                    context.fill(path, with: .color(Color.white.opacity(0.82)))
                } else {
                    context.fill(path, with: .color(Color.white.opacity(0.30)))
                }
            }

            for key in layout.blackKeys {
                let path = Path(roundedRect: key.rect, cornerRadius: 2)
                if held.contains(key.note) {
                    context.fill(path, with: .color(IslandTheme.accent))
                } else if !hasScale || scaleNotes.contains(PitchClass(key.note)) {
                    context.fill(path, with: .color(Color(white: 0.13)))
                } else {
                    context.fill(path, with: .color(Color(white: 0.13)))
                    context.fill(path, with: .color(Color.black.opacity(0.55)))
                }
                context.stroke(path, with: .color(.black), lineWidth: 1)
            }

            guard showsOctaveLabels, size.height >= 40 else { return }
            for key in layout.whiteKeys where PitchClass(key.note).value == 0 {
                let text = Text(MIDINote.name(key.note))
                    .font(.system(size: min(9, key.rect.width * 0.62),
                                  weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(held.contains(key.note) ? 0.55 : 0.42))
                context.draw(text, at: CGPoint(x: key.rect.midX, y: size.height - 8),
                             anchor: .center)
            }
        }
    }
}
