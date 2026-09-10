import Foundation

/// What a note is doing inside a chord.
///
/// Colouring keys by this is worth more than colouring them all alike: the root
/// and the third are what you need to see to know what you played, and picking
/// them out of a voicing by eye is exactly the skill being learned.
public enum ChordToneRole: String, Sendable, Hashable, CaseIterable {
    case root, third, fifth, seventh, tension
}

/// A named chord: a root, a quality, and optionally a bass note that is not the
/// root. `Chord` is spelling-aware, so it can render `Ab7` with a G♭ rather than
/// an F♯ without consulting anything else.
public struct Chord: Hashable, Sendable, CustomStringConvertible {
    public let root: SpelledNote
    public let quality: ChordQuality
    /// The sounding bass note when it differs from the root. `nil` means root position.
    public let bass: SpelledNote?

    public init(root: SpelledNote, quality: ChordQuality, bass: SpelledNote? = nil) {
        self.root = root
        self.quality = quality
        self.bass = bass?.pitchClass == root.pitchClass ? nil : bass
    }

    public var pitchClasses: Set<PitchClass> {
        var set = Set(quality.pitchClassOffsets.map { PitchClass(root.pitchClass.value + $0) })
        if let bass { set.insert(bass.pitchClass) }
        return set
    }

    /// Every chord tone with its interval and correct spelling, lowest degree first.
    public var spelledTones: [(interval: Interval, note: SpelledNote)] {
        quality.tones
            .sorted { $0.interval.semitones < $1.interval.semitones }
            .map { (interval: $0.interval, note: root.spelled(degree: $0.interval.degree, semitones: $0.interval.semitones)) }
    }

    /// 0 = root position, 1 = third in the bass, and so on. `nil` when the bass
    /// is not a chord tone at all, which is a true slash chord like `C/F#`.
    public var inversion: Int? {
        guard let bass else { return 0 }
        let sorted = quality.tones
            .sorted { (($0.interval.semitones % 12) + 12) % 12 < (($1.interval.semitones % 12) + 12) % 12 }
        let offset = root.pitchClass.distance(to: bass.pitchClass)
        return sorted.firstIndex { ((($0.interval.semitones % 12) + 12) % 12) == offset }
    }

    public func symbol(unicode: Bool = false) -> String {
        guard let bass else { return root.name(unicode: unicode) + quality.symbol }
        // `6/9` already contains a slash; without parentheses `Gm6/9/C` reads as
        // though it had two bass notes.
        let suffix = quality.symbol.contains("/") ? "(\(quality.symbol))" : quality.symbol
        return root.name(unicode: unicode) + suffix + "/" + bass.name(unicode: unicode)
    }

    public var description: String { symbol() }

    /// The chord symbol written in a chosen naming system. Only the root and
    /// bass change; the quality suffix is the same in every system.
    public func symbol(naming: NoteNaming, in key: Key? = nil, unicode: Bool = false) -> String {
        let rootText = naming.name(root, in: key, unicode: unicode)
        let figure = naming.figure(quality.symbol)
        guard let bass else { return rootText + figure }
        let suffix = quality.symbol.contains("/") ? "(\(figure))" : figure
        return rootText + suffix + "/" + naming.name(bass, in: key, unicode: unicode)
    }

    /// Spoken description stays in letters whatever the notation.
    ///
    /// "1 dominant thirteenth" is not something anybody says; prose wants a
    /// note name even when the symbol above it is a number.
    public func spokenName(naming: NoteNaming, in key: Key? = nil) -> String {
        fullName(naming: naming.isNumeric ? .letters : naming, in: key)
    }

    /// Correct spelling for each pitch class in this chord, so a keyboard can
    /// label a held key the way the chord spells it rather than guessing.
    public var spellingByPitchClass: [Int: SpelledNote] {
        var map: [Int: SpelledNote] = [:]
        for (_, note) in spelledTones { map[note.pitchClass.value] = note }
        if let bass { map[bass.pitchClass.value] = bass }
        return map
    }

    public func fullName(naming: NoteNaming, in key: Key? = nil) -> String {
        var text = "\(naming.name(root, in: key)) \(quality.name)"
        if let bass {
            let ordinals = ["root position", "first inversion", "second inversion",
                            "third inversion", "fourth inversion", "fifth inversion"]
            if let inv = inversion, inv > 0, inv < ordinals.count {
                text += ", \(ordinals[inv])"
            } else {
                text += " over \(naming.name(bass, in: key))"
            }
        }
        return text
    }

    /// Spoken description used in the island's expanded state.
    public var fullName: String {
        var text = "\(root.name()) \(quality.name)"
        if let bass {
            let ordinals = ["root position", "first inversion", "second inversion",
                            "third inversion", "fourth inversion", "fifth inversion"]
            if let inv = inversion, inv > 0, inv < ordinals.count {
                text += ", \(ordinals[inv])"
            } else {
                text += " over \(bass.name())"
            }
        }
        return text
    }

    /// What role a pitch class plays in this chord, if any.
    public func role(of pc: PitchClass) -> ChordToneRole? {
        let offset = root.pitchClass.distance(to: pc)
        guard let tone = quality.tones.first(where: {
            ((($0.interval.semitones % 12) + 12) % 12) == offset
        }) else { return nil }
        switch tone.interval.degree {
        case 1: return .root
        case 3: return .third
        case 5: return .fifth
        case 7: return .seventh
        default: return .tension
        }
    }

    /// Re-spell the same sounding chord for a different key context.
    public func respelled(in key: Key?) -> Chord {
        let newRoot = Chord.bestRootSpelling(for: root.pitchClass, quality: quality, key: key)
        let newBass = bass.map { b in
            SpelledNote.natural(b.pitchClass, preferFlats: key?.preferFlats ?? (newRoot.alteration < 0))
        }
        return Chord(root: newRoot, quality: quality, bass: newBass)
    }

    /// Choose between enharmonic root spellings (D♭ vs C♯) by asking which one
    /// spells the whole chord with fewer and simpler accidentals, with the key
    /// signature breaking ties.
    public static func bestRootSpelling(for pc: PitchClass, quality: ChordQuality, key: Key?) -> SpelledNote {
        var options: [SpelledNote] = [
            SpelledNote.natural(pc, preferFlats: false),
            SpelledNote.natural(pc, preferFlats: true),
        ]
        // Consider the rarer spellings too, so G♭ and F♯ both get a fair hearing.
        for letter in Letter.allCases {
            for alt in -1...1 where alt != 0 {
                let candidate = SpelledNote(letter, alt)
                if candidate.pitchClass == pc && !options.contains(candidate) {
                    options.append(candidate)
                }
            }
        }

        func cost(_ note: SpelledNote) -> Double {
            var total = 0.0
            // Prefer fewer accidentals across the whole chord. Double
            // accidentals are only mildly discouraged, because some qualities
            // genuinely require one: the seventh of Cdim7 *is* B double-flat,
            // and penalising that heavily is how detectors end up printing the
            // absurd B#dim7 instead.
            for tone in quality.tones {
                let spelled = note.spelled(degree: tone.interval.degree, semitones: tone.interval.semitones)
                total += Double(abs(spelled.alteration))
                if abs(spelled.alteration) >= 2 { total += 1.0 }
            }
            total += Double(abs(note.alteration)) * 0.5
            // Roots past the ends of the circle of fifths are not spellings
            // anyone uses. B# is twelve fifths from C; rule it out rather than
            // letting a cheap accidental count argue for it.
            total += Double(max(0, abs(note.fifths) - 7)) * 5.0
            if let key {
                if key.contains(note.pitchClass) { total -= 2.0 }
                // Match the key's accidental direction: flat keys spell flat.
                if key.preferFlats && note.alteration > 0 { total += 3.0 }
                if !key.preferFlats && note.alteration < 0 { total += 1.5 }
            }
            return total
        }

        return options.min { cost($0) < cost($1) } ?? options[0]
    }
}
