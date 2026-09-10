import Foundation

/// Every scale Chordware knows.
///
/// The modal families are *generated* by rotating their parent scale rather than
/// typed out, so all forty-nine seven-note modes come from seven interval arrays
/// and cannot drift out of sync with each other. Only the genuinely irregular
/// scales — pentatonics, bebop, symmetric and folk scales — are listed by hand.
public enum ScaleLibrary {
    /// Rotate a parent scale to produce its modes.
    private static func modes(parentID: String,
                              _ parent: [Int],
                              _ names: [(String, [String])],
                              _ category: ScaleCategory) -> [Scale] {
        let n = parent.count
        return names.enumerated().map { degree, entry in
            let (name, aliases) = entry
            let rotated = (0..<n).map { step -> Int in
                ((parent[(degree + step) % n] - parent[degree]) % 12 + 12) % 12
            }
            return Scale(
                id: name.lowercased().replacingOccurrences(of: " ", with: "-")
                    .replacingOccurrences(of: "\u{266D}", with: "b")
                    .replacingOccurrences(of: "\u{266F}", with: "s"),
                name: name,
                intervals: rotated.sorted(),
                category: category,
                aliases: aliases,
                parentID: parentID,
                modeDegree: degree + 1
            )
        }
    }

    private static func s(_ id: String, _ name: String, _ intervals: [Int],
                          _ category: ScaleCategory, _ aliases: [String] = []) -> Scale {
        Scale(id: id, name: name, intervals: intervals, category: category, aliases: aliases)
    }

    public static let all: [Scale] = {
        var scales: [Scale] = []

        scales += modes(parentID: "ionian", [0, 2, 4, 5, 7, 9, 11], [
            ("Ionian", ["Major"]), ("Dorian", []), ("Phrygian", []), ("Lydian", []),
            ("Mixolydian", []), ("Aeolian", ["Natural Minor"]), ("Locrian", []),
        ], .majorModes)

        scales += modes(parentID: "melodic-minor", [0, 2, 3, 5, 7, 9, 11], [
            ("Melodic Minor", ["Jazz Minor"]), ("Dorian b2", ["Phrygian \u{266E}6"]),
            ("Lydian Augmented", []), ("Lydian Dominant", ["Acoustic", "Overtone"]),
            ("Mixolydian b6", ["Hindu"]), ("Locrian \u{266E}2", ["Half Diminished"]),
            ("Altered", ["Super Locrian", "Diminished Whole Tone"]),
        ], .melodicMinorModes)

        scales += modes(parentID: "harmonic-minor", [0, 2, 3, 5, 7, 8, 11], [
            ("Harmonic Minor", []), ("Locrian \u{266E}6", []), ("Ionian #5", []),
            ("Dorian #4", ["Ukrainian Dorian", "Romanian Minor"]),
            ("Phrygian Dominant", ["Spanish Phrygian", "Ahava Raba"]),
            ("Lydian #2", []), ("Altered Diminished", ["Ultralocrian"]),
        ], .harmonicMinorModes)

        scales += modes(parentID: "harmonic-major", [0, 2, 4, 5, 7, 8, 11], [
            ("Harmonic Major", []), ("Dorian b5", []), ("Phrygian b4", []),
            ("Lydian b3", ["Melodic Minor #4"]), ("Mixolydian b2", []),
            ("Lydian Augmented #2", []), ("Locrian bb7", []),
        ], .harmonicMajorModes)

        scales += modes(parentID: "double-harmonic", [0, 1, 4, 5, 7, 8, 11], [
            ("Double Harmonic", ["Byzantine", "Arabic", "Gypsy Major"]),
            ("Lydian #2 #6", []), ("Ultraphrygian", []),
            ("Hungarian Minor", ["Gypsy Minor"]), ("Oriental", []),
            ("Ionian #2 #5", []), ("Locrian bb3 bb7", []),
        ], .doubleHarmonicModes)

        scales += modes(parentID: "neapolitan-minor", [0, 1, 3, 5, 7, 8, 11], [
            ("Neapolitan Minor", []), ("Lydian #6", []), ("Mixolydian Augmented", []),
            ("Hungarian Gypsy", []), ("Locrian Dominant", []),
            ("Ionian #2", []), ("Ultralocrian bb3", []),
        ], .neapolitanMinorModes)

        scales += modes(parentID: "neapolitan-major", [0, 1, 3, 5, 7, 9, 11], [
            ("Neapolitan Major", []), ("Leading Whole Tone", []),
            ("Lydian Augmented Dominant", []), ("Lydian Dominant b6", []),
            ("Major Locrian", []), ("Half Diminished b4", []),
            ("Altered Dominant bb3", []),
        ], .neapolitanMajorModes)

        scales += [
            s("major-pentatonic", "Major Pentatonic", [0, 2, 4, 7, 9], .pentatonic),
            s("minor-pentatonic", "Minor Pentatonic", [0, 3, 5, 7, 10], .pentatonic),
            s("suspended-pentatonic", "Suspended Pentatonic", [0, 2, 5, 7, 10], .pentatonic, ["Egyptian"]),
            s("man-gong", "Man Gong", [0, 3, 5, 8, 10], .pentatonic, ["Blues Minor Pentatonic"]),
            s("ritusen", "Ritusen", [0, 2, 5, 7, 9], .pentatonic, ["Blues Major Pentatonic", "Scottish"]),
            s("hirajoshi", "Hirajoshi", [0, 2, 3, 7, 8], .pentatonic),
            s("in-sen", "In Sen", [0, 1, 5, 7, 10], .pentatonic),
            s("iwato", "Iwato", [0, 1, 5, 6, 10], .pentatonic),
            s("kumoi", "Kumoi", [0, 2, 3, 7, 9], .pentatonic),
            s("pelog", "Balinese Pelog", [0, 1, 3, 7, 8], .pentatonic),
            s("chinese", "Chinese", [0, 4, 6, 7, 11], .pentatonic),
            s("dominant-pentatonic", "Dominant Pentatonic", [0, 2, 4, 7, 10], .pentatonic),
            s("scriabin", "Scriabin", [0, 1, 4, 7, 9], .pentatonic),

            s("blues", "Blues", [0, 3, 5, 6, 7, 10], .blues, ["Blues Hexatonic"]),
            s("major-blues", "Major Blues", [0, 2, 3, 4, 7, 9], .blues),
            s("blues-nonatonic", "Blues Nonatonic", [0, 2, 3, 4, 5, 7, 9, 10, 11], .blues),

            s("bebop-dominant", "Bebop Dominant", [0, 2, 4, 5, 7, 9, 10, 11], .bebop),
            s("bebop-major", "Bebop Major", [0, 2, 4, 5, 7, 8, 9, 11], .bebop),
            s("bebop-dorian", "Bebop Dorian", [0, 2, 3, 4, 5, 7, 9, 10], .bebop, ["Bebop Minor"]),
            s("bebop-melodic-minor", "Bebop Melodic Minor", [0, 2, 3, 5, 7, 8, 9, 11], .bebop),
            s("bebop-harmonic-minor", "Bebop Harmonic Minor", [0, 2, 3, 5, 7, 8, 10, 11], .bebop),

            s("whole-tone", "Whole Tone", [0, 2, 4, 6, 8, 10], .symmetric),
            s("diminished-wh", "Diminished (whole-half)", [0, 2, 3, 5, 6, 8, 9, 11], .symmetric, ["Octatonic"]),
            s("diminished-hw", "Diminished (half-whole)", [0, 1, 3, 4, 6, 7, 9, 10], .symmetric, ["Dominant Diminished"]),
            s("augmented", "Augmented", [0, 3, 4, 7, 8, 11], .symmetric),
            s("tritone", "Tritone", [0, 1, 4, 6, 7, 10], .symmetric),
            s("two-semitone-tritone", "Two-Semitone Tritone", [0, 1, 2, 6, 7, 8], .symmetric),
            s("messiaen-5", "Messiaen Mode 5", [0, 1, 5, 6, 7, 11], .symmetric),
            s("six-tone-symmetrical", "Six Tone Symmetrical", [0, 1, 4, 5, 8, 9], .symmetric),
            s("chromatic", "Chromatic", Array(0..<12), .symmetric),

            s("hungarian-major", "Hungarian Major", [0, 3, 4, 6, 7, 9, 10], .exotic),
            s("enigmatic", "Enigmatic", [0, 1, 4, 6, 8, 10, 11], .exotic),
            s("prometheus", "Prometheus", [0, 2, 4, 6, 9, 10], .exotic),
            s("prometheus-neapolitan", "Prometheus Neapolitan", [0, 1, 4, 6, 9, 10], .exotic),
            s("arabian", "Arabian", [0, 2, 4, 5, 6, 8, 10], .exotic),
            s("persian", "Persian", [0, 1, 4, 5, 6, 8, 11], .exotic),
            s("algerian", "Algerian", [0, 2, 3, 6, 7, 8, 11], .exotic),
            s("spanish-eight-tone", "Spanish 8-Tone", [0, 1, 3, 4, 5, 6, 8, 10], .exotic),
            s("flamenco", "Flamenco", [0, 1, 4, 5, 7, 8, 11], .exotic),
            s("istrian", "Istrian", [0, 1, 3, 4, 6, 7], .exotic),
            s("locrian-major", "Locrian Major", [0, 2, 4, 5, 6, 8, 10], .exotic),
            s("harmonic-phrygian", "Harmonic Phrygian", [0, 1, 3, 5, 7, 8, 11], .exotic),
            s("jazz-dominant", "Jazz Dominant", [0, 2, 4, 5, 7, 9, 10], .exotic),
        ]

        return scales
    }()

    private static let byID: [String: Scale] = Dictionary(all.map { ($0.id, $0) }) { a, _ in a }

    public static func scale(id: String) -> Scale? { byID[id] }

    public static func scales(in category: ScaleCategory) -> [Scale] {
        all.filter { $0.category == category }
    }

    public static var categories: [ScaleCategory] { ScaleCategory.allCases }

    /// Case-insensitive search over names and aliases, for the CLI and the
    /// scale browser's search field.
    public static func search(_ query: String) -> [Scale] {
        let q = query.lowercased()
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.name.lowercased().contains(q)
                || $0.id.contains(q)
                || $0.aliases.contains { $0.lowercased().contains(q) }
        }
    }

    /// Scales whose notes exactly match a set of pitch classes.
    public static func matching(pitchClasses: Set<PitchClass>, root: PitchClass) -> [Scale] {
        all.filter { $0.pitchClassSet(root: root) == pitchClasses }
    }
}
