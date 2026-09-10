import Foundation

public enum KeyMode: String, Sendable, Hashable, CaseIterable {
    case major, minor

    public var scaleOffsets: [Int] {
        switch self {
        case .major: return [0, 2, 4, 5, 7, 9, 11]
        // Natural minor. Harmonic and melodic degrees are handled by the
        // analysis layer as alterations rather than as separate keys.
        case .minor: return [0, 2, 3, 5, 7, 8, 10]
        }
    }
}

/// A tonal centre. Chordware treats key as context rather than truth: it
/// improves chord spelling and enables Roman numerals, and the user can always
/// override the estimate.
public struct Key: Hashable, Sendable, CustomStringConvertible {
    public let tonic: SpelledNote
    public let mode: KeyMode

    public init(tonic: SpelledNote, mode: KeyMode) {
        self.tonic = tonic
        self.mode = mode
    }

    public var pitchClasses: Set<PitchClass> {
        Set(mode.scaleOffsets.map { PitchClass(tonic.pitchClass.value + $0) })
    }

    /// Position on the circle of fifths, negative on the flat side. C major and
    /// A minor are 0; E♭ major is -3; E major is +4.
    public var fifths: Int {
        let letterPosition = [0, 2, 4, -1, 1, 3, 5][tonic.letter.rawValue] // C D E F G A B
        let base = letterPosition + 7 * tonic.alteration
        return mode == .major ? base : base - 3
    }

    /// Flat keys should spell with flats. This is what keeps an E♭ blues from
    /// rendering `D#7` in the island.
    public var preferFlats: Bool { fifths < 0 }

    /// Diatonic triad and seventh qualities, degree by degree.
    public var diatonicQualityIDs: [String] {
        switch mode {
        case .major: return ["maj7", "m7", "m7", "maj7", "7", "m7", "m7b5"]
        case .minor: return ["m7", "m7b5", "maj7", "m7", "m7", "maj7", "7"]
        }
    }

    public func scaleDegree(of pc: PitchClass) -> Int? {
        let offset = tonic.pitchClass.distance(to: pc)
        return mode.scaleOffsets.firstIndex(of: offset).map { $0 + 1 }
    }

    public func contains(_ pc: PitchClass) -> Bool { pitchClasses.contains(pc) }

    public var name: String { "\(tonic.name()) \(mode.rawValue)" }
    /// Abbreviated form for tight layouts such as the island's collapsed strip.
    public var shortName: String { "\(tonic.name()) \(mode == .major ? "maj" : "min")" }
    public var description: String { name }

    /// Spell the tonic of every key the estimator can report, choosing the
    /// conventional written form for each (D♭ major, not C♯ major).
    public static let allKeys: [Key] = {
        let majorTonics = ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
        let minorTonics = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "G#", "A", "Bb", "B"]
        var keys: [Key] = []
        for name in majorTonics { if let n = SpelledNote(name) { keys.append(Key(tonic: n, mode: .major)) } }
        for name in minorTonics { if let n = SpelledNote(name) { keys.append(Key(tonic: n, mode: .minor)) } }
        return keys
    }()
}
