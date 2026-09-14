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
    /// The key, so a held key is labelled the way the music means it.
    public var key: Key?
    /// Widest a white key may be drawn.
    public var maxWhiteWidth: CGFloat
    public var lowNote: Int
    public var octaves: Int
    /// Label each C, so the octave you are looking at is unambiguous.
    public var showsOctaveLabels: Bool
    /// Name the keys currently held, for teaching and for screen recording.
    public var namesHeldNotes: Bool
    /// Only for spelling the labels: Bb and A# are the same key and not the
    /// same note. Nothing here is coloured by what a note is doing.
    public var chord: Chord?
    public var palette: Theme.Palette

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
                key: Key? = nil,
                palette: Theme.Palette = Theme.standard,
                maxWhiteWidth: CGFloat = PianoLayout.maxWhiteWidth) {
        self.heldNotes = heldNotes
        self.key = key
        self.maxWhiteWidth = maxWhiteWidth
        self.showsOctaveLabels = showsOctaveLabels
        self.namesHeldNotes = namesHeldNotes
        self.chord = chord
        self.palette = palette

        let lowest = min(heldNotes.min() ?? Self.defaultLow, Self.defaultLow)
        let highest = max(heldNotes.max() ?? Self.defaultHigh, Self.defaultHigh)
        let floorC = (lowest / 12) * 12
        let ceilC = ((highest + 11) / 12) * 12
        self.lowNote = lowNote ?? floorC
        self.octaves = octaves ?? max(1, (ceilC - floorC) / 12)
    }

    public var body: some View {
        Canvas { context, size in
            let layout = PianoLayout(lowNote: lowNote, octaves: octaves, size: size,
                                     maxWhiteWidth: maxWhiteWidth)
            let held = Set(heldNotes)
            let radius: CGFloat = 2

            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Theme.surfaceHigh))

            // A held key is filled, and that is the whole of it.
            //
            // It used to sink two points, take a shadow gradient under the
            // finger, a lit bevel above its front lip and a blurred glow off
            // its edges. All of that says "this key moved", which is not the
            // question -- you can feel that, your finger is on it. The question
            // is *which* keys, answered by one flat vivid colour that reads from
            // across a room and cannot be mistaken for a rendering fault.
            for key in layout.whiteKeys {
                let rect = key.rect.insetBy(dx: 0.5, dy: 0)
                let path = Path(roundedRect: rect, cornerRadius: radius)
                if held.contains(key.note) {
                    context.fill(path, with: .color(palette.whiteKey))
                } else {
                    context.fill(path, with: .linearGradient(
                        Gradient(colors: [Color(red: 0.965, green: 0.968, blue: 0.972),
                                          Color(red: 0.870, green: 0.878, blue: 0.890)]),
                        startPoint: CGPoint(x: rect.midX, y: rect.minY),
                        endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                }
                context.stroke(path, with: .color(Color.black.opacity(0.35)), lineWidth: 0.5)
            }

            for key in layout.blackKeys {
                let path = Path(roundedRect: key.rect, cornerRadius: radius)
                if held.contains(key.note) {
                    context.fill(path, with: .color(palette.blackKey))
                } else {
                    context.fill(path, with: .linearGradient(
                        Gradient(colors: [Color(red: 0.185, green: 0.192, blue: 0.205),
                                          Color(red: 0.055, green: 0.058, blue: 0.066)]),
                        startPoint: CGPoint(x: key.rect.midX, y: key.rect.minY),
                        endPoint: CGPoint(x: key.rect.midX, y: key.rect.maxY)))
                }
            }

            let whiteWidth = layout.whiteKeys.first?.rect.width ?? 0

            if namesHeldNotes, whiteWidth >= 11 {
                for key in layout.keys where held.contains(key.note) {
                    // Three sources of truth about a black key's name, in
                    // order. The chord's own spelling first, so a label and the
                    // chord name cannot disagree about Bb versus A#. Then the
                    // key, which is still tracked even though nothing on screen
                    // says what it is. Then flats, because nothing has said
                    // otherwise and walking D - C - Bb is far more common than
                    // walking D - C - A#: in the keys people actually play in,
                    // the black notes are flats.
                    let pitchClass = PitchClass(key.note)
                    // The chord's own spelling wins when there is one, so a
                    // label and the chord name cannot disagree. Otherwise the
                    // pitch class is named the same way every loose note in the
                    // app is named, which is the only way the keyboard and the
                    // caption above it stay in step.
                    let name = chord?.spellingByPitchClass[pitchClass.value]
                        .map { NoteNaming.letters.name($0, in: self.key, unicode: true) }
                        ?? NoteNaming.letters.name(pitchClass, in: self.key, unicode: true)
                    // With its octave: walking D4 down to C4 down to Bb3 is a
                    // different thing from playing three notes called D, C and
                    // Bb, and the keyboard is the only place that difference can
                    // be read. An octave digit is a third character on a key
                    // that is already narrow, so the type gives a little.
                    let label = name + "\(MIDINote.octave(key.note))"
                    let pointSize = min(10, whiteWidth * 0.46)
                    let text = Text(label)
                        .font(.system(size: pointSize, weight: .bold, design: .rounded))
                        .foregroundStyle(key.isBlack ? palette.blackKeyLabel
                                                     : palette.whiteKeyLabel)
                    // Black keys are short, so their label sits at their own
                    // foot; white keys carry theirs at the bottom of the board.
                    let y = key.isBlack ? key.rect.maxY - 9 : size.height - 9
                    context.draw(text, at: CGPoint(x: key.rect.midX, y: y), anchor: .center)
                }
            }

            guard showsOctaveLabels, size.height >= 40 else { return }
            for key in layout.whiteKeys where PitchClass(key.note).value == 0 {
                guard !held.contains(key.note) else { continue }
                let text = Text(MIDINote.name(key.note))
                    .font(.system(size: min(9, key.rect.width * 0.5),
                                  weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.40))
                context.draw(text, at: CGPoint(x: key.rect.midX, y: size.height - 8),
                             anchor: .center)
            }
        }
    }
}
