import Foundation

/// How much a tone matters to a chord's identity.
public enum ToneRole: Sendable, Hashable {
    /// Remove it and the chord is something else. Missing one disqualifies a match.
    case essential
    /// Conventionally present but freely omitted — almost always the fifth.
    case optional
    /// Legal colour inside this quality that need not be voiced. The 9th of a
    /// 13th chord is the usual case: nice if there, not missed if absent.
    case color
}

public struct ChordTone: Hashable, Sendable {
    public let interval: Interval
    public let role: ToneRole

    public init(interval: Interval, role: ToneRole) {
        self.interval = interval
        self.role = role
    }
}

/// Broad category, used for colour-coding and functional analysis.
public enum ChordFamily: String, Sendable, Hashable, CaseIterable {
    case major, minor, dominant, diminished, augmented, suspended, other
}

/// A chord type independent of root: "minor seventh", not "D minor seventh".
public struct ChordQuality: Hashable, Sendable, Identifiable {
    public let id: String
    /// Suffix written after the root: `m7`, `maj9`, `7#11`.
    public let symbol: String
    /// Spoken form: "minor seventh".
    public let name: String
    public let family: ChordFamily
    public let tones: [ChordTone]
    /// Alternate spellings the parser accepts: `-7`, `min7`, `mi7`.
    public let aliases: [String]

    public var intervals: [Interval] { tones.map(\.interval) }

    /// Semitone offsets from the root, folded into one octave.
    public var pitchClassOffsets: Set<Int> {
        Set(tones.map { ((($0.interval.semitones % 12) + 12) % 12) })
    }

    public func tones(with role: ToneRole) -> [ChordTone] { tones.filter { $0.role == role } }

    /// Number of distinct pitch classes when fully voiced.
    public var cardinality: Int { pitchClassOffsets.count }
}

private let e = ToneRole.essential
private let o = ToneRole.optional
private let c = ToneRole.color

private func mk(_ id: String, _ symbol: String, _ name: String, _ family: ChordFamily,
                _ tones: [(Int, Int, ToneRole)], _ aliases: [String] = []) -> ChordQuality {
    ChordQuality(
        id: id, symbol: symbol, name: name, family: family,
        tones: tones.map { ChordTone(interval: Interval(degree: $0.0, semitones: $0.1), role: $0.2) },
        aliases: aliases
    )
}

public enum ChordDictionary {
    /// Every quality Chordware can name, ordered roughly simple-to-complex.
    ///
    /// Intervals are written as (degree, semitones) so extensions spell
    /// correctly: a ♯11 is degree 11 at 18 semitones, which resolves to F♯ over
    /// C rather than G♭. The fifth is `optional` nearly everywhere because
    /// players drop it constantly; thirds and sevenths are `essential` because
    /// dropping one genuinely changes the chord.
    public static let all: [ChordQuality] = [
        // Triads
        mk("maj", "", "major", .major, [(1, 0, e), (3, 4, e), (5, 7, o)], ["M", "maj"]),
        mk("min", "m", "minor", .minor, [(1, 0, e), (3, 3, e), (5, 7, o)], ["-", "min", "mi"]),
        mk("dim", "dim", "diminished", .diminished, [(1, 0, e), (3, 3, e), (5, 6, e)], ["o", "\u{00B0}"]),
        mk("aug", "aug", "augmented", .augmented, [(1, 0, e), (3, 4, e), (5, 8, e)], ["+", "#5"]),
        mk("sus2", "sus2", "suspended second", .suspended, [(1, 0, e), (2, 2, e), (5, 7, e)]),
        mk("sus4", "sus4", "suspended fourth", .suspended, [(1, 0, e), (4, 5, e), (5, 7, e)], ["sus"]),
        mk("five", "5", "power chord", .other, [(1, 0, e), (5, 7, e)], ["no3"]),

        // Sixths
        mk("6", "6", "major sixth", .major, [(1, 0, e), (3, 4, e), (5, 7, o), (6, 9, e)], ["maj6", "M6"]),
        mk("m6", "m6", "minor sixth", .minor, [(1, 0, e), (3, 3, e), (5, 7, o), (6, 9, e)], ["min6", "-6"]),
        mk("69", "6/9", "six-nine", .major, [(1, 0, e), (3, 4, e), (5, 7, o), (6, 9, e), (9, 14, e)], ["6add9", "69"]),
        mk("m69", "m6/9", "minor six-nine", .minor, [(1, 0, e), (3, 3, e), (5, 7, o), (6, 9, e), (9, 14, e)], ["m69"]),

        // Sevenths
        mk("maj7", "maj7", "major seventh", .major, [(1, 0, e), (3, 4, e), (5, 7, o), (7, 11, e)], ["M7", "\u{0394}", "ma7"]),
        mk("7", "7", "dominant seventh", .dominant, [(1, 0, e), (3, 4, e), (5, 7, o), (7, 10, e)], ["dom7"]),
        mk("m7", "m7", "minor seventh", .minor, [(1, 0, e), (3, 3, e), (5, 7, o), (7, 10, e)], ["-7", "min7", "mi7"]),
        mk("mMaj7", "mMaj7", "minor-major seventh", .minor, [(1, 0, e), (3, 3, e), (5, 7, o), (7, 11, e)], ["mM7", "-M7", "minMaj7"]),
        mk("m7b5", "m7b5", "half-diminished seventh", .diminished, [(1, 0, e), (3, 3, e), (5, 6, e), (7, 10, e)], ["\u{00F8}", "\u{00F8}7", "halfdim"]),
        mk("dim7", "dim7", "diminished seventh", .diminished, [(1, 0, e), (3, 3, e), (5, 6, e), (7, 9, e)], ["o7", "\u{00B0}7"]),
        mk("dimMaj7", "dimMaj7", "diminished major seventh", .diminished, [(1, 0, e), (3, 3, e), (5, 6, e), (7, 11, e)], ["oM7"]),
        mk("7sus4", "7sus4", "dominant seventh suspended fourth", .suspended, [(1, 0, e), (4, 5, e), (5, 7, o), (7, 10, e)], ["7sus"]),
        mk("7sus2", "7sus2", "dominant seventh suspended second", .suspended, [(1, 0, e), (2, 2, e), (5, 7, o), (7, 10, e)]),
        mk("7#5", "7#5", "dominant seventh sharp five", .dominant, [(1, 0, e), (3, 4, e), (5, 8, e), (7, 10, e)], ["aug7", "7+"]),
        mk("7b5", "7b5", "dominant seventh flat five", .dominant, [(1, 0, e), (3, 4, e), (5, 6, e), (7, 10, e)]),
        mk("maj7#5", "maj7#5", "major seventh sharp five", .augmented, [(1, 0, e), (3, 4, e), (5, 8, e), (7, 11, e)], ["augMaj7", "M7+"]),
        mk("maj7b5", "maj7b5", "major seventh flat five", .major, [(1, 0, e), (3, 4, e), (5, 6, e), (7, 11, e)]),

        // Added-note chords, no seventh
        mk("add9", "add9", "added ninth", .major, [(1, 0, e), (3, 4, e), (5, 7, o), (9, 14, e)], ["add2", "2"]),
        mk("madd9", "m(add9)", "minor added ninth", .minor, [(1, 0, e), (3, 3, e), (5, 7, o), (9, 14, e)], ["madd2", "-add9"]),
        mk("add11", "add11", "added eleventh", .major, [(1, 0, e), (3, 4, e), (5, 7, o), (11, 17, e)], ["add4"]),
        mk("madd11", "m(add11)", "minor added eleventh", .minor, [(1, 0, e), (3, 3, e), (5, 7, o), (11, 17, e)]),
        mk("sus4add9", "sus4(add9)", "suspended fourth added ninth", .suspended, [(1, 0, e), (4, 5, e), (5, 7, o), (9, 14, e)], ["sus4add2"]),

        // Ninths
        mk("maj9", "maj9", "major ninth", .major, [(1, 0, e), (3, 4, e), (5, 7, o), (7, 11, e), (9, 14, e)], ["M9", "\u{0394}9"]),
        mk("9", "9", "dominant ninth", .dominant, [(1, 0, e), (3, 4, e), (5, 7, o), (7, 10, e), (9, 14, e)]),
        mk("m9", "m9", "minor ninth", .minor, [(1, 0, e), (3, 3, e), (5, 7, o), (7, 10, e), (9, 14, e)], ["-9", "min9"]),
        mk("mMaj9", "mMaj9", "minor-major ninth", .minor, [(1, 0, e), (3, 3, e), (5, 7, o), (7, 11, e), (9, 14, e)], ["mM9"]),
        mk("m9b5", "m9b5", "half-diminished ninth", .diminished, [(1, 0, e), (3, 3, e), (5, 6, e), (7, 10, e), (9, 14, e)], ["\u{00F8}9"]),
        mk("7b9", "7b9", "dominant seventh flat nine", .dominant, [(1, 0, e), (3, 4, e), (5, 7, o), (7, 10, e), (9, 13, e)]),
        mk("7#9", "7#9", "dominant seventh sharp nine", .dominant, [(1, 0, e), (3, 4, e), (5, 7, o), (7, 10, e), (9, 15, e)]),
        mk("9#5", "9#5", "dominant ninth sharp five", .dominant, [(1, 0, e), (3, 4, e), (5, 8, e), (7, 10, e), (9, 14, e)], ["aug9"]),
        mk("9b5", "9b5", "dominant ninth flat five", .dominant, [(1, 0, e), (3, 4, e), (5, 6, e), (7, 10, e), (9, 14, e)]),
        mk("9sus4", "9sus4", "dominant ninth suspended fourth", .suspended, [(1, 0, e), (4, 5, e), (5, 7, o), (7, 10, e), (9, 14, e)], ["11"]),

        // Elevenths
        mk("m11", "m11", "minor eleventh", .minor, [(1, 0, e), (3, 3, e), (5, 7, o), (7, 10, e), (9, 14, c), (11, 17, e)], ["-11", "min11"]),
        mk("maj9#11", "maj9#11", "major ninth sharp eleven", .major, [(1, 0, e), (3, 4, e), (5, 7, o), (7, 11, e), (9, 14, c), (11, 18, e)], ["lydian"]),
        mk("7#11", "7#11", "dominant seventh sharp eleven", .dominant, [(1, 0, e), (3, 4, e), (5, 7, o), (7, 10, e), (9, 14, c), (11, 18, e)]),
        mk("maj7#11", "maj7#11", "major seventh sharp eleven", .major, [(1, 0, e), (3, 4, e), (5, 7, o), (7, 11, e), (11, 18, e)]),
        mk("m11b5", "m11b5", "half-diminished eleventh", .diminished, [(1, 0, e), (3, 3, e), (5, 6, e), (7, 10, e), (11, 17, e)]),

        // Thirteenths
        mk("13", "13", "dominant thirteenth", .dominant, [(1, 0, e), (3, 4, e), (5, 7, o), (7, 10, e), (9, 14, c), (13, 21, e)]),
        mk("m13", "m13", "minor thirteenth", .minor, [(1, 0, e), (3, 3, e), (5, 7, o), (7, 10, e), (9, 14, c), (11, 17, c), (13, 21, e)], ["-13"]),
        mk("maj13", "maj13", "major thirteenth", .major, [(1, 0, e), (3, 4, e), (5, 7, o), (7, 11, e), (9, 14, c), (13, 21, e)], ["M13", "\u{0394}13"]),
        mk("13sus4", "13sus4", "dominant thirteenth suspended fourth", .suspended, [(1, 0, e), (4, 5, e), (5, 7, o), (7, 10, e), (9, 14, c), (13, 21, e)]),
        mk("7b13", "7b13", "dominant seventh flat thirteen", .dominant, [(1, 0, e), (3, 4, e), (7, 10, e), (13, 20, e)]),
        mk("13b9", "13b9", "dominant thirteenth flat nine", .dominant, [(1, 0, e), (3, 4, e), (5, 7, o), (7, 10, e), (9, 13, e), (13, 21, e)]),
        mk("13#11", "13#11", "dominant thirteenth sharp eleven", .dominant, [(1, 0, e), (3, 4, e), (5, 7, o), (7, 10, e), (9, 14, c), (11, 18, e), (13, 21, e)]),

        // Altered dominants
        mk("7#9#5", "7#9#5", "dominant seventh sharp nine sharp five", .dominant, [(1, 0, e), (3, 4, e), (5, 8, e), (7, 10, e), (9, 15, e)]),
        mk("7b9#5", "7b9#5", "dominant seventh flat nine sharp five", .dominant, [(1, 0, e), (3, 4, e), (5, 8, e), (7, 10, e), (9, 13, e)]),
        mk("7b9#11", "7b9#11", "dominant seventh flat nine sharp eleven", .dominant, [(1, 0, e), (3, 4, e), (5, 7, o), (7, 10, e), (9, 13, e), (11, 18, e)]),
        mk("7alt", "7alt", "altered dominant", .dominant, [(1, 0, e), (3, 4, e), (7, 10, e), (9, 13, c), (9, 15, c), (11, 18, c), (13, 20, c)], ["alt"]),
    ]

    private static let byID: [String: ChordQuality] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func quality(id: String) -> ChordQuality? { byID[id] }

    /// Every written form, longest first — used by the parser to bite off the
    /// largest suffix it can before giving up.
    public static let symbolsByLength: [(String, ChordQuality)] = {
        var pairs: [(String, ChordQuality)] = []
        for q in all {
            pairs.append((q.symbol, q))
            for alias in q.aliases { pairs.append((alias, q)) }
        }
        return pairs.sorted { $0.0.count > $1.0.count }
    }()
}
