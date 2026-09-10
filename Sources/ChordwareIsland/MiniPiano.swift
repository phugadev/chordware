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
    /// How held keys are named.
    public var naming: NoteNaming
    /// The key, needed when names are relative to it.
    public var key: Key?
    /// Colour held keys by their role rather than all alike.
    public var usesRoleColors: Bool
    public var lowNote: Int
    public var octaves: Int
    /// Label each C, so the octave you are looking at is unambiguous.
    public var showsOctaveLabels: Bool
    /// Name the keys currently held, for teaching and for screen recording.
    public var namesHeldNotes: Bool
    /// Colours held keys by their role in this chord, when there is one.
    public var chord: Chord?
    /// Velocity per note. A harder strike shows as a more saturated key.
    public var velocities: [Int: Int]

    /// C2 to C6, which covers where chords are actually voiced.
    private static let defaultLow = 36
    private static let defaultHigh = 84

    /// The range is fixed by default, and only stretches for notes outside it.
    ///
    /// Sizing it to each voicing looks fine in a still and is horrible in
    /// motion: every chord change resizes the whole keyboard, so the eye has to
    /// re-find middle C constantly.
    public init(heldNotes: [Int],
                lowNote: Int? = nil, octaves: Int? = nil,
                showsOctaveLabels: Bool = false,
                namesHeldNotes: Bool = false,
                chord: Chord? = nil,
                velocities: [Int: Int] = [:],
                naming: NoteNaming = .letters,
                key: Key? = nil,
                usesRoleColors: Bool = true) {
        self.heldNotes = heldNotes
        self.naming = naming
        self.key = key
        self.usesRoleColors = usesRoleColors
        self.showsOctaveLabels = showsOctaveLabels
        self.namesHeldNotes = namesHeldNotes
        self.chord = chord
        self.velocities = velocities

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
                let base = usesRoleColors
                    ? IslandTheme.roleColor(chord?.role(of: PitchClass(note)))
                    : IslandTheme.accent
                guard let velocity = velocities[note] else { return base }
                // Never below half: a softly played note must still read as
                // clearly pressed, not as a key that failed to draw.
                let strength = 0.55 + 0.45 * (Double(velocity) / 127.0)
                return base.opacity(min(1, strength))
            }

            for key in layout.whiteKeys {
                let rect = key.rect.insetBy(dx: 0.5, dy: 0)
                let path = Path(roundedRect: rect, cornerRadius: 2)
                context.fill(path, with: .color(Color.white.opacity(0.82)))
                if held.contains(key.note) {
                    context.fill(path, with: .color(heldColor(key.note)))
                }
            }

            for key in layout.blackKeys {
                let path = Path(roundedRect: key.rect, cornerRadius: 2)
                context.fill(path, with: .color(Color(white: 0.13)))
                if held.contains(key.note) {
                    context.fill(path, with: .color(heldColor(key.note)))
                }
                context.stroke(path, with: .color(.black), lineWidth: 1)
            }

            let whiteWidth = layout.whiteKeys.first?.rect.width ?? 0

            if namesHeldNotes, whiteWidth >= 11 {
                for key in layout.keys where held.contains(key.note) {
                    // Prefer the chord's own spelling, so a keyboard label and
                    // the note list cannot disagree about Bb versus A#.
                    let spelling = chord?.spellingByPitchClass[PitchClass(key.note).value]
                    let name = spelling.map { naming.name($0, in: self.key, unicode: true) }
                        ?? naming.name(PitchClass(key.note), in: self.key, unicode: true)
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
                // Octave labels stay absolute landmarks, so a relative system
                // falls back to letters here.
                let label = naming == .scaleDegrees
                    ? MIDINote.name(key.note)
                    : naming.name(PitchClass(key.note), in: self.key, unicode: true)
                        + "\(MIDINote.octave(key.note))"
                let text = Text(label)
                    .font(.system(size: min(9, key.rect.width * 0.55),
                                  weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.42))
                context.draw(text, at: CGPoint(x: key.rect.midX, y: size.height - 9),
                             anchor: .center)
            }
        }
    }
}
