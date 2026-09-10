import Foundation

/// How to write note names.
///
/// Letters are not universal. Most of the Spanish, Italian, French and
/// Portuguese speaking world learns fixed do, where Do is always C — a naming
/// system, not the movable-do ear-training one. Session players read numbers.
/// All three describe the same notes.
public enum NoteNaming: String, Sendable, Hashable, CaseIterable, Codable {
    /// C D E F G A B.
    case letters
    /// Do Re Mi Fa Sol La Si, with Do fixed to C.
    case fixedDo
    /// 1–7 relative to the key, with accidentals: the Nashville system.
    case scaleDegrees

    public var displayName: String {
        switch self {
        case .letters: return "Letters (C D E)"
        case .fixedDo: return "Do Re Mi"
        case .scaleDegrees: return "Numbers (Nashville)"
        }
    }

    /// Needs a key to mean anything.
    public var requiresKey: Bool { self == .scaleDegrees }

    private static let syllables = ["Do", "Re", "Mi", "Fa", "Sol", "La", "Si"]

    /// Render a note. Falls back to letters when a key is needed and absent.
    public func name(_ note: SpelledNote, in key: Key? = nil, unicode: Bool = false) -> String {
        switch self {
        case .letters:
            return note.name(unicode: unicode)
        case .fixedDo:
            return Self.syllables[note.letter.rawValue] + note.accidentalString(unicode: unicode)
        case .scaleDegrees:
            guard let key else { return note.name(unicode: unicode) }
            return Self.degreeName(note, in: key, unicode: unicode)
        }
    }

    /// A pitch class has no spelling of its own, so one is chosen from the key.
    public func name(_ pc: PitchClass, in key: Key? = nil, unicode: Bool = false) -> String {
        let spelled = SpelledNote.natural(pc, preferFlats: key?.preferFlats ?? false)
        return name(spelled, in: key, unicode: unicode)
    }

    /// Scale degree with an accidental, read from the note letters so that a
    /// flat third and a sharp second stay distinct.
    private static func degreeName(_ note: SpelledNote, in key: Key, unicode: Bool) -> String {
        let index = ((note.letter.rawValue - key.tonic.letter.rawValue) % 7 + 7) % 7
        let expected = key.mode.scaleOffsets[index]
        let actual = key.tonic.pitchClass.distance(to: note.pitchClass)
        var alteration = actual - expected
        if alteration > 6 { alteration -= 12 }
        if alteration < -6 { alteration += 12 }

        let mark: String
        switch alteration {
        case 0: mark = ""
        case ..<0: mark = String(repeating: unicode ? "\u{266D}" : "b", count: -alteration)
        default: mark = String(repeating: unicode ? "\u{266F}" : "#", count: alteration)
        }
        return mark + "\(index + 1)"
    }
}
