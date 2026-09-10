import Foundation

public enum ScaleCategory: String, Sendable, Hashable, CaseIterable {
    case majorModes = "Major modes"
    case melodicMinorModes = "Melodic minor modes"
    case harmonicMinorModes = "Harmonic minor modes"
    case harmonicMajorModes = "Harmonic major modes"
    case doubleHarmonicModes = "Double harmonic modes"
    case neapolitanMinorModes = "Neapolitan minor modes"
    case neapolitanMajorModes = "Neapolitan major modes"
    case pentatonic = "Pentatonic"
    case blues = "Blues"
    case bebop = "Bebop"
    case symmetric = "Symmetric"
    case exotic = "Other scales"
}

/// A scale as a set of semitone offsets from its root, plus enough metadata to
/// present it. Roots are applied at use time, so one `Scale` covers all twelve.
public struct Scale: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// Ascending semitone offsets from the root, always starting at 0.
    public let intervals: [Int]
    public let category: ScaleCategory
    public let aliases: [String]
    /// The parent scale this is a mode of, when it is one.
    public let parentID: String?
    /// Which degree of the parent it starts on (1-based).
    public let modeDegree: Int?

    public init(id: String, name: String, intervals: [Int], category: ScaleCategory,
                aliases: [String] = [], parentID: String? = nil, modeDegree: Int? = nil) {
        self.id = id
        self.name = name
        self.intervals = intervals
        self.category = category
        self.aliases = aliases
        self.parentID = parentID
        self.modeDegree = modeDegree
    }

    public var noteCount: Int { intervals.count }

    public func pitchClasses(root: PitchClass) -> [PitchClass] {
        intervals.map { PitchClass(root.value + $0) }
    }

    public func pitchClassSet(root: PitchClass) -> Set<PitchClass> {
        Set(pitchClasses(root: root))
    }

    public func contains(_ pc: PitchClass, root: PitchClass) -> Bool {
        intervals.contains(root.distance(to: pc))
    }

    /// Spell the scale from a root, so E♭ Dorian reads E♭ F G♭ A♭ B♭ C D♭ rather
    /// than a mix of sharps and flats. Seven-note scales get one letter per
    /// degree; other sizes fall back to a sensible chromatic spelling.
    public func spelled(root: SpelledNote) -> [SpelledNote] {
        if intervals.count == 7 {
            return intervals.enumerated().map { index, semitones in
                root.spelled(degree: index + 1, semitones: semitones)
            }
        }

        // Scales that are not seven-note cannot take one letter per degree, so
        // choose letters greedily: prefer an unused letter, prefer fewer
        // accidentals, and lean the way the scale already leans. Without this a
        // C blues comes out with a D# in it instead of an Eb.
        let leansFlat = intervals.contains(3) || root.alteration < 0
        var usedLetters = Set<Int>()
        var result: [SpelledNote] = []

        for semitones in intervals {
            let target = PitchClass(root.pitchClass.value + semitones)
            var best: SpelledNote?
            var bestCost = Double.infinity
            for letter in Letter.allCases {
                var alt = target.value - letter.naturalSemitone
                alt = ((alt % 12) + 12) % 12
                if alt > 6 { alt -= 12 }
                guard abs(alt) <= 2 else { continue }
                var cost = Double(abs(alt)) * 2.0
                if usedLetters.contains(letter.rawValue) { cost += 1.5 }
                if alt != 0 && ((alt < 0) != leansFlat) { cost += 0.5 }
                if cost < bestCost { bestCost = cost; best = SpelledNote(letter, alt) }
            }
            let note = best ?? SpelledNote.natural(target, preferFlats: leansFlat)
            usedLetters.insert(note.letter.rawValue)
            result.append(note)
        }
        return result
    }

    /// Build a seventh chord on each degree by stacking scale thirds, then ask
    /// the detector to name it. Reusing the detector here means the diatonic
    /// palette agrees with live detection by construction.
    public func diatonicChords(root: SpelledNote, seventh: Bool = true) -> [Chord?] {
        let count = intervals.count
        guard count >= 5 else { return [] }
        let steps = seventh ? [0, 2, 4, 6] : [0, 2, 4]
        return (0..<count).map { degree in
            let pcs = steps.map { step -> Int in
                let idx = (degree + step) % count
                let octaves = (degree + step) / count
                return root.pitchClass.value + intervals[idx] + 12 * octaves
            }
            let key = Key(tonic: root, mode: intervals.contains(3) ? .minor : .major)
            let options = ChordDetector.Options(key: key, allowRootless: false, maxCandidates: 1)
            // Voice it from a fixed octave so the degree's own note is the bass.
            let midi = pcs.map { 48 + $0 - root.pitchClass.value }
            return ChordDetector.detect(midiNotes: midi, options: options).first?.chord
        }
    }

    /// The scale's notes written in a naming system.
    ///
    /// Degrees are read against the scale's own root, not the current key: a
    /// scale is a shape, and "1 2 3 4 5 6 b7" describes Mixolydian wherever it
    /// starts.
    public func spelled(root: SpelledNote, naming: NoteNaming, key: Key? = nil) -> [String] {
        let reference = naming.isNumeric
            ? Key(tonic: root, mode: intervals.contains(3) ? .minor : .major)
            : key
        return spelled(root: root).map { naming.name($0, in: reference) }
    }

    /// How well this scale covers a chord.
    ///
    /// Only *essential* tones are required. Demanding every template tone would
    /// rule out the correct answers: the altered scale has no natural fifth, so
    /// a strict subset test rejects it for C7#9 even though that is exactly the
    /// scale a player wants — and exactly the voicing they use, fifth omitted.
    public func fitScore(for chord: Chord, root: PitchClass) -> Double? {
        let scaleSet = pitchClassSet(root: root)
        let chordRoot = chord.root.pitchClass

        for tone in chord.quality.tones where tone.role == .essential {
            guard scaleSet.contains(PitchClass(chordRoot.value + tone.interval.semitones)) else {
                return nil
            }
        }

        var score = 1.0
        for tone in chord.quality.tones where tone.role != .essential {
            if !scaleSet.contains(PitchClass(chordRoot.value + tone.interval.semitones)) {
                score -= 0.08
            }
        }
        if let bass = chord.bass, !scaleSet.contains(bass.pitchClass) { score -= 0.10 }
        // Prefer the tightest scale that still covers the chord, so the
        // chromatic scale — which fits everything and says nothing — sinks.
        score -= Double(max(0, scaleSet.count - chord.quality.tones.count)) * 0.04
        return score
    }
}

public enum ChordScaleMap {
    /// Scales that contain every note of the chord, best fit first.
    ///
    /// Ranked by tightness rather than by any fixed chord-scale table, so an
    /// altered dominant surfaces the altered scale ahead of the chromatic one
    /// without needing the relationship hard-coded.
    public static func scales(for chord: Chord, limit: Int = 8) -> [(scale: Scale, root: SpelledNote, score: Double)] {
        var results: [(Scale, SpelledNote, Double)] = []
        let chordRoot = chord.root.pitchClass
        for scale in ScaleLibrary.all {
            // Scales rooted on the chord root are the useful answer for a
            // player; modes rooted elsewhere are the same notes renamed.
            guard let score = scale.fitScore(for: chord, root: chordRoot) else { continue }
            results.append((scale, chord.root, score))
        }
        return results
            .sorted { ($0.2, -Double($0.0.noteCount)) > ($1.2, -Double($1.0.noteCount)) }
            .prefix(limit)
            .map { (scale: $0.0, root: $0.1, score: $0.2) }
    }
}
