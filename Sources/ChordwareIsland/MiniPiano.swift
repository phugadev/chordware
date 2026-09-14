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
    /// Widest a white key may be drawn.
    public var maxWhiteWidth: CGFloat
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
                usesRoleColors: Bool = true,
                maxWhiteWidth: CGFloat = PianoLayout.maxWhiteWidth) {
        self.heldNotes = heldNotes
        self.naming = naming
        self.key = key
        self.usesRoleColors = usesRoleColors
        self.maxWhiteWidth = maxWhiteWidth
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

    /// The visible face on the front of a white key.
    private let lipHeight: CGFloat = 3

    public var body: some View {
        Canvas { context, size in
            let layout = PianoLayout(lowNote: lowNote, octaves: octaves, size: size,
                                     maxWhiteWidth: maxWhiteWidth)
            let held = Set(heldNotes)

            // Keys are drawn as keys, always. Dimming the ones outside the key
            // signature was tried and it reads as damage rather than as
            // annotation: in F major every B natural went dark, which looks
            // exactly like a rendering fault sitting next to every C. Scale
            // membership is a dot instead, which is clearly deliberate.
            func heldColor(_ note: Int) -> Color {
                let role = chord?.role(of: PitchClass(note))
                let base = IslandTheme.roleColor(usesRoleColors ? role : nil)
                guard let velocity = velocities[note] else { return base }
                // Never below three-quarters. Velocity is a nuance on top of
                // "this key is down"; fading the colour towards the key
                // underneath makes a softly played note look like one that
                // failed to draw, which is the more expensive mistake.
                let strength = 0.78 + 0.22 * (Double(velocity) / 127.0)
                return base.opacity(min(1, strength))
            }

            // Keys are drawn as objects with a top, a front and an edge,
            // rather than as filled rectangles. A piano is the largest thing in
            // this window and a flat rounded rect reads as a wireframe of one.
            let radius = min(3.0, layout.whiteKeys.first?.rect.width ?? 3 / 6)

            // The keybed the keys sit in, so they are in something rather than
            // floating on the background.
            context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: size.height)),
                         with: .color(IslandTheme.surfaceHigh))

            for key in layout.whiteKeys {
                let rect = key.rect.insetBy(dx: 0.5, dy: 0)
                let pressed = held.contains(key.note)
                // A pressed key sinks: it starts lower and ends at the same
                // place, so the front lip shortens the way a real one does.
                let top = pressed ? rect.minY + 2 : rect.minY
                let body = CGRect(x: rect.minX, y: top, width: rect.width,
                                  height: rect.maxY - top)
                let path = Path(roundedRect: body, cornerRadius: radius)

                if pressed {
                    context.fill(path, with: .color(heldColor(key.note)))
                    // Deep in shadow at the back, where the finger is, opening
                    // out towards the front. A flat fill of the same colour
                    // reads as coloured paper laid on the key rather than as
                    // the key itself going down.
                    context.fill(path, with: .linearGradient(
                        Gradient(colors: [Color.black.opacity(0.42), .clear]),
                        startPoint: CGPoint(x: body.midX, y: body.minY),
                        endPoint: CGPoint(x: body.midX, y: body.minY + body.height * 0.62)))
                    // The front face, in shadow because the key has tipped
                    // away, with the bevel above it catching the light. Two
                    // lines is all it takes for a rectangle to have a front.
                    let lip = CGRect(x: body.minX, y: body.maxY - lipHeight,
                                     width: body.width, height: lipHeight)
                    context.fill(Path(roundedRect: lip, cornerRadius: radius),
                                 with: .color(Color.black.opacity(0.34)))
                    context.fill(Path(CGRect(x: body.minX + 0.5, y: lip.minY - 1,
                                             width: body.width - 1, height: 1)),
                                 with: .color(Color.white.opacity(0.34)))
                } else {
                    // Ivory, not paper. Warm whites put more distance between
                    // the keys and the cool blues and violets that land on
                    // them, and a piano key has never been blue-grey.
                    context.fill(path, with: .linearGradient(
                        Gradient(colors: [Color(red: 0.968, green: 0.962, blue: 0.944),
                                          Color(red: 0.822, green: 0.812, blue: 0.788)]),
                        startPoint: CGPoint(x: body.midX, y: body.minY),
                        endPoint: CGPoint(x: body.midX, y: body.maxY)))
                    // The front lip: the face you actually see on an upright.
                    let lip = CGRect(x: body.minX, y: body.maxY - lipHeight,
                                     width: body.width, height: lipHeight)
                    context.fill(Path(roundedRect: lip, cornerRadius: radius),
                                 with: .color(Color(red: 0.706, green: 0.696, blue: 0.672)))
                }
                // Hairline between keys instead of a gap.
                context.stroke(path, with: .color(Color.black.opacity(0.35)), lineWidth: 0.5)
            }

            for key in layout.blackKeys {
                let pressed = held.contains(key.note)
                let top = pressed ? key.rect.minY + 1.5 : key.rect.minY
                let body = CGRect(x: key.rect.minX, y: top, width: key.rect.width,
                                  height: key.rect.maxY - top)
                let path = Path(roundedRect: body, cornerRadius: radius)

                // Cast onto the white keys either side, which is most of what
                // makes a black key read as sitting above them.
                let shadow = CGRect(x: body.minX - 1, y: body.minY,
                                    width: body.width + 2, height: body.height + 2)
                context.fill(Path(roundedRect: shadow, cornerRadius: radius),
                             with: .color(Color.black.opacity(0.30)))

                if pressed {
                    context.fill(path, with: .color(heldColor(key.note)))
                    context.fill(path, with: .linearGradient(
                        Gradient(colors: [Color.black.opacity(0.38), .clear]),
                        startPoint: CGPoint(x: body.midX, y: body.minY),
                        endPoint: CGPoint(x: body.midX, y: body.midY)))
                    // The same lit bevel the unpressed keys have, so a pressed
                    // black key is still recognisably one of them.
                    let cap = CGRect(x: body.minX + 1, y: body.maxY - body.height * 0.09,
                                     width: body.width - 2, height: body.height * 0.06)
                    context.fill(Path(roundedRect: cap, cornerRadius: 1),
                                 with: .color(Color.white.opacity(0.30)))
                } else {
                    context.fill(path, with: .linearGradient(
                        Gradient(colors: [Color(red: 0.175, green: 0.182, blue: 0.205),
                                          Color(red: 0.055, green: 0.058, blue: 0.070)]),
                        startPoint: CGPoint(x: body.midX, y: body.minY),
                        endPoint: CGPoint(x: body.midX, y: body.maxY)))
                    // The lit top edge, where the light catches the bevel.
                    let cap = CGRect(x: body.minX + 1, y: body.maxY - body.height * 0.10,
                                     width: body.width - 2, height: body.height * 0.07)
                    context.fill(Path(roundedRect: cap, cornerRadius: 1),
                                 with: .color(Color.white.opacity(0.16)))
                }
            }

            // A struck key throws light onto what is around it, and that is
            // the single thing separating a keyboard being played from a
            // diagram of one.
            //
            // A blurred copy of the key's own shape, not a big soft ellipse
            // centred on it. The ellipse version spread light across two keys
            // either side and, added onto white keys that are already near the
            // top of the range, came out as a milky smear rather than as glow.
            // Light that hugs the edge it is coming off is the whole effect;
            // past about a key's width it is haze.
            context.drawLayer { glow in
                glow.blendMode = .plusLighter
                glow.addFilter(.blur(radius: 5))
                for key in layout.keys where held.contains(key.note) {
                    let colour = heldColor(key.note)
                    glow.fill(Path(roundedRect: key.rect.insetBy(dx: -0.5, dy: -0.5),
                                   cornerRadius: radius),
                              with: .color(colour.opacity(0.22)))
                }
            }

            let whiteWidth = layout.whiteKeys.first?.rect.width ?? 0

            if namesHeldNotes, whiteWidth >= 11 {
                for key in layout.keys where held.contains(key.note) {
                    // Prefer the chord's own spelling, so a keyboard label and
                    // the note list cannot disagree about Bb versus A#.
                    let spelling = chord?.spellingByPitchClass[PitchClass(key.note).value]
                    let name = spelling.map { naming.name($0, in: self.key, unicode: true) }
                        ?? naming.name(PitchClass(key.note), in: self.key, unicode: true)
                    // White on every held key. It used to be black on the
                    // white ones, which was right when they were pale and is
                    // unreadable now they are not.
                    let text = Text(name)
                        .font(.system(size: min(11, whiteWidth * 0.7),
                                      weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
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
                    .foregroundStyle(Color.black.opacity(0.38))
                context.draw(text, at: CGPoint(x: key.rect.midX, y: size.height - 9),
                             anchor: .center)
            }
        }
    }
}
