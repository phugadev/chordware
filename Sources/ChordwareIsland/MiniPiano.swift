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
    /// Notes belonging to the current scale, marked with a dot beneath the key.
    public var scaleNotes: Set<PitchClass>
    public var lowNote: Int
    public var octaves: Int
    /// Label each C, so the octave you are looking at is unambiguous.
    public var showsOctaveLabels: Bool
    /// Name the keys currently held, for teaching and for screen recording.
    public var namesHeldNotes: Bool
    /// Colours held keys by their role in this chord, when there is one.
    public var chord: Chord?

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
                showsOctaveLabels: Bool = false,
                namesHeldNotes: Bool = false,
                chord: Chord? = nil) {
        self.heldNotes = heldNotes
        self.scaleNotes = scaleNotes
        self.showsOctaveLabels = showsOctaveLabels
        self.namesHeldNotes = namesHeldNotes
        self.chord = chord

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

            // Keys are drawn as keys, always. Dimming the ones outside the key
            // signature was tried and it reads as damage rather than as
            // annotation: in F major every B natural went dark, which looks
            // exactly like a rendering fault sitting next to every C. Scale
            // membership is a dot instead, which is clearly deliberate.
            func heldColor(_ note: Int) -> Color {
                IslandTheme.roleColor(chord?.role(of: PitchClass(note)))
            }

            for key in layout.whiteKeys {
                let rect = key.rect.insetBy(dx: 0.5, dy: 0)
                let path = Path(roundedRect: rect, cornerRadius: 2)
                context.fill(path, with: .color(held.contains(key.note)
                                                ? heldColor(key.note)
                                                : Color.white.opacity(0.82)))
            }

            for key in layout.blackKeys {
                let path = Path(roundedRect: key.rect, cornerRadius: 2)
                context.fill(path, with: .color(held.contains(key.note)
                                                ? heldColor(key.note)
                                                : Color(white: 0.13)))
                context.stroke(path, with: .color(.black), lineWidth: 1)
            }

            let whiteWidth = layout.whiteKeys.first?.rect.width ?? 0
            let dotSize = max(3.0, min(5.0, whiteWidth * 0.22))

            if !scaleNotes.isEmpty, size.height >= 40 {
                for key in layout.keys where scaleNotes.contains(PitchClass(key.note)) {
                    guard !held.contains(key.note) else { continue }
                    // A C already carries its octave label; a dot on top of it
                    // is two marks fighting for the same few pixels.
                    if showsOctaveLabels, !key.isBlack, PitchClass(key.note).value == 0 { continue }
                    let y = key.isBlack ? key.rect.maxY - dotSize * 1.8 : size.height - dotSize * 3.2
                    let dot = CGRect(x: key.rect.midX - dotSize / 2, y: y,
                                     width: dotSize, height: dotSize)
                    context.fill(Path(ellipseIn: dot),
                                 with: .color(key.isBlack
                                              ? Color.white.opacity(0.38)
                                              : Color.black.opacity(0.26)))
                }
            }

            if namesHeldNotes, whiteWidth >= 11 {
                for key in layout.keys where held.contains(key.note) {
                    let name = SpelledNote.natural(PitchClass(key.note),
                                                   preferFlats: true).name(unicode: true)
                    let text = Text(name)
                        .font(.system(size: min(11, whiteWidth * 0.7),
                                      weight: .bold, design: .rounded))
                        .foregroundStyle(key.isBlack ? Color.white : Color.black.opacity(0.75))
                    let y = key.isBlack ? key.rect.maxY - 10 : size.height - 10
                    context.draw(text, at: CGPoint(x: key.rect.midX, y: y), anchor: .center)
                }
            }

            guard showsOctaveLabels, size.height >= 40 else { return }
            for key in layout.whiteKeys where PitchClass(key.note).value == 0 {
                guard !held.contains(key.note) else { continue }
                let text = Text(MIDINote.name(key.note))
                    .font(.system(size: min(9, key.rect.width * 0.62),
                                  weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.42))
                context.draw(text, at: CGPoint(x: key.rect.midX, y: size.height - 9),
                             anchor: .center)
            }
        }
    }
}
