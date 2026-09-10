import Foundation

/// A pitch class: one of the twelve notes of the chromatic scale, with octave
/// discarded. 0 is C. Arithmetic wraps, so `PitchClass(-1) == PitchClass(11)`.
public struct PitchClass: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let value: Int

    public init(_ raw: Int) {
        value = ((raw % 12) + 12) % 12
    }

    public static func < (a: PitchClass, b: PitchClass) -> Bool { a.value < b.value }

    public static func + (pc: PitchClass, semitones: Int) -> PitchClass {
        PitchClass(pc.value + semitones)
    }

    public static func - (pc: PitchClass, semitones: Int) -> PitchClass {
        PitchClass(pc.value - semitones)
    }

    /// Ascending distance in semitones from `self` up to `other`.
    public func distance(to other: PitchClass) -> Int {
        PitchClass(other.value - value).value
    }

    /// Sharp-flavoured name. Only for debugging and contexts with no key —
    /// real display names come from `SpelledNote`, which knows the chord.
    public var sharpName: String {
        ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"][value]
    }

    public var description: String { sharpName }
}

/// Middle C is MIDI 60, which is C4 in the convention Logic and most DAWs use.
public enum MIDINote {
    public static func pitchClass(_ note: Int) -> PitchClass { PitchClass(note) }
    public static func octave(_ note: Int) -> Int { note / 12 - 1 }

    /// Frequency in Hz at A440.
    public static func frequency(_ note: Int, tuning: Double = 440.0) -> Double {
        tuning * pow(2.0, (Double(note) - 69.0) / 12.0)
    }

    /// Nearest MIDI note to a frequency, and how many cents sharp it is.
    public static func nearest(frequency: Double, tuning: Double = 440.0) -> (note: Int, cents: Double) {
        guard frequency > 0 else { return (0, 0) }
        let exact = 69.0 + 12.0 * log2(frequency / tuning)
        let note = Int(exact.rounded())
        return (note, (exact - Double(note)) * 100.0)
    }
}

public extension MIDINote {
    /// Parse scientific pitch notation — `C4`, `F#3`, `Bb5`, `Ebb2` — into a MIDI
    /// note number, using the convention that middle C (60) is C4.
    static func parse(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // Split the trailing octave (which may be negative) from the note name.
        var idx = trimmed.endIndex
        var digits = ""
        while idx > trimmed.startIndex {
            let prev = trimmed.index(before: idx)
            let ch = trimmed[prev]
            if ch.isNumber || ch == "-" { digits.insert(ch, at: digits.startIndex); idx = prev } else { break }
        }
        guard let octave = Int(digits), idx > trimmed.startIndex,
              let note = SpelledNote(String(trimmed[trimmed.startIndex..<idx])) else { return nil }
        // Use the letter's natural position so Cb4 lands just below C4.
        let natural = note.letter.naturalSemitone
        return (octave + 1) * 12 + natural + note.alteration
    }

    /// Parse a whitespace-separated list of note names.
    static func parseList(_ text: String) -> [Int]? {
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        let notes = parts.compactMap { parse($0) }
        return notes.count == parts.count ? notes : nil
    }

    /// Render a MIDI note as scientific pitch notation.
    static func name(_ note: Int, preferFlats: Bool = false) -> String {
        SpelledNote.natural(PitchClass(note), preferFlats: preferFlats).name() + "\(octave(note))"
    }
}
