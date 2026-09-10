import Foundation

/// The seven note letters, in ascending order from C.
public enum Letter: Int, CaseIterable, Sendable, Comparable {
    case c = 0, d, e, f, g, a, b

    /// Semitones above C for the natural (unaltered) letter.
    public var naturalSemitone: Int { [0, 2, 4, 5, 7, 9, 11][rawValue] }

    public var name: String { ["C", "D", "E", "F", "G", "A", "B"][rawValue] }

    /// Move `steps` diatonic steps up (or down, if negative), wrapping.
    public func advanced(by steps: Int) -> Letter {
        Letter(rawValue: ((rawValue + steps) % 7 + 7) % 7)!
    }

    public static func < (a: Letter, b: Letter) -> Bool { a.rawValue < b.rawValue }

    public init?(character: Character) {
        guard let idx = ["C", "D", "E", "F", "G", "A", "B"]
            .firstIndex(of: String(character).uppercased()) else { return nil }
        self.init(rawValue: idx)
    }
}

/// A note with a *spelling* — a letter plus an alteration — not just a pitch
/// class. G# and Ab are the same key on a piano but different notes on paper,
/// and picking the right one is most of what makes chord symbols readable.
public struct SpelledNote: Hashable, Sendable, CustomStringConvertible {
    public let letter: Letter
    /// Semitone offset from the natural letter: -2 = double flat, +2 = double sharp.
    public let alteration: Int

    public init(_ letter: Letter, _ alteration: Int = 0) {
        self.letter = letter
        self.alteration = alteration
    }

    public var pitchClass: PitchClass { PitchClass(letter.naturalSemitone + alteration) }

    /// Accidental rendered with ASCII (`Bb`, `F#`) or Unicode (`B♭`, `F♯`).
    public func accidentalString(unicode: Bool) -> String {
        switch alteration {
        case -2: return unicode ? "\u{1D12B}" : "bb"
        case -1: return unicode ? "\u{266D}" : "b"
        case 0: return ""
        case 1: return unicode ? "\u{266F}" : "#"
        case 2: return unicode ? "\u{1D12A}" : "##"
        default:
            let mark = alteration < 0 ? (unicode ? "\u{266D}" : "b") : (unicode ? "\u{266F}" : "#")
            return String(repeating: mark, count: abs(alteration))
        }
    }

    public func name(unicode: Bool = false) -> String {
        letter.name + accidentalString(unicode: unicode)
    }

    public var description: String { name() }

    /// Spell the note `degree` scale-steps and `semitones` semitones above this
    /// one. This is the whole trick: the letter comes from the degree, the
    /// accidental is then whatever makes the pitch class come out right.
    ///
    /// From Ab, degree 7 / 10 semitones gives G♭ — letter G because it is the
    /// seventh letter up from A, flat because G♮ would be 11 semitones.
    public func spelled(degree: Int, semitones: Int) -> SpelledNote {
        let targetLetter = letter.advanced(by: degree - 1)
        let targetPC = PitchClass(pitchClass.value + semitones).value
        // Signed distance from the natural letter to the target, folded into -6...5.
        var alt = targetPC - targetLetter.naturalSemitone
        alt = ((alt % 12) + 12) % 12
        if alt > 6 { alt -= 12 }
        return SpelledNote(targetLetter, alt)
    }

    /// Position on the circle of fifths, C = 0, negative on the flat side.
    /// Real music lives roughly within ±7 (C♯ major to C♭ major); anything
    /// beyond that — B♯, F♭♭ — is a spelling nobody writes.
    public var fifths: Int {
        [0, 2, 4, -1, 1, 3, 5][letter.rawValue] + 7 * alteration
    }

    /// Parse `C`, `F#`, `Bb`, `Ebb`, `A♯`. Case-insensitive on the letter.
    public init?(_ text: String) {
        var chars = Array(text.trimmingCharacters(in: .whitespaces))
        guard let first = chars.first, let letter = Letter(character: first) else { return nil }
        chars.removeFirst()
        var alt = 0
        for ch in chars {
            switch ch {
            case "b", "\u{266D}": alt -= 1
            case "#", "\u{266F}": alt += 1
            case "x", "\u{1D12A}": alt += 2
            case "\u{1D12B}": alt -= 2
            case "\u{266E}": break
            default: return nil
            }
        }
        self.init(letter, alt)
    }

    /// A default spelling for a pitch class when there is no chord or key to
    /// consult. Prefers flats or sharps per `preferFlats`.
    public static func natural(_ pc: PitchClass, preferFlats: Bool = false) -> SpelledNote {
        let sharp: [(Letter, Int)] = [
            (.c, 0), (.c, 1), (.d, 0), (.d, 1), (.e, 0), (.f, 0),
            (.f, 1), (.g, 0), (.g, 1), (.a, 0), (.a, 1), (.b, 0),
        ]
        let flat: [(Letter, Int)] = [
            (.c, 0), (.d, -1), (.d, 0), (.e, -1), (.e, 0), (.f, 0),
            (.g, -1), (.g, 0), (.a, -1), (.a, 0), (.b, -1), (.b, 0),
        ]
        let table = preferFlats ? flat : sharp
        let (l, a) = table[pc.value]
        return SpelledNote(l, a)
    }
}
