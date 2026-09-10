import Foundation

public enum HarmonicFunction: String, Sendable, Hashable, CaseIterable {
    case tonic = "T"
    case subdominant = "S"
    case dominant = "D"
    case chromatic = "X"

    public var name: String {
        switch self {
        case .tonic: return "tonic"
        case .subdominant: return "subdominant"
        case .dominant: return "dominant"
        case .chromatic: return "chromatic"
        }
    }
}

public struct RomanNumeral: Sendable, Hashable, CustomStringConvertible {
    /// The rendered numeral: `V7`, `vii\u{00F8}7`, `bVII`, `V7/ii`.
    public let symbol: String
    /// Scale degree 1...7, read from the note letters so it survives spelling.
    public let degree: Int
    /// Chromatic alteration of the degree: -1 for a flat root, +1 for a sharp.
    public let accidental: Int
    public let function: HarmonicFunction
    public let isDiatonic: Bool
    /// Why this chord is unusual, when it is: "secondary dominant of ii",
    /// "borrowed from the parallel minor", "Neapolitan".
    public let explanation: String?
    /// For secondary function, the numeral being tonicised.
    public let target: String?

    public var description: String { symbol }
}

public enum RomanNumeralAnalyzer {
    private static let numerals = ["I", "II", "III", "IV", "V", "VI", "VII"]

    /// Figures written after the numeral, by chord quality.
    private static func figure(for quality: ChordQuality) -> String {
        switch quality.id {
        case "maj", "min": return ""
        case "dim": return "\u{00B0}"
        case "aug": return "+"
        case "7": return "7"
        case "maj7": return "maj7"
        case "m7": return "7"
        case "mMaj7": return "maj7"
        case "m7b5": return "\u{00F8}7"
        case "dim7": return "\u{00B0}7"
        case "6", "m6": return "6"
        case "sus4": return "sus4"
        case "sus2": return "sus2"
        case "7sus4": return "7sus4"
        case "five": return "5"
        default: return quality.symbol
        }
    }

    private static func isLowercase(_ quality: ChordQuality) -> Bool {
        switch quality.family {
        case .minor, .diminished: return true
        default: return false
        }
    }

    private static func accidentalPrefix(_ alteration: Int) -> String {
        if alteration == 0 { return "" }
        return String(repeating: alteration < 0 ? "b" : "#", count: abs(alteration))
    }

    /// Pitch classes counted as belonging to the key. Minor keys include the
    /// raised seventh, because V7 and vii\u{00B0}7 in minor are ordinary rather than
    /// chromatic and labelling them `#vii\u{00B0}7` would be wrong.
    private static func extendedKeyPitchClasses(_ key: Key) -> Set<PitchClass> {
        var set = key.pitchClasses
        if key.mode == .minor {
            set.insert(PitchClass(key.tonic.pitchClass.value + 11))
        }
        return set
    }

    /// Analyse a chord in a key. Passing the chord that follows sharpens the
    /// reading of ambiguous chromatic chords, which frequently only differ by
    /// where they resolve.
    public static func analyze(_ chord: Chord, in key: Key, resolvingTo next: Chord? = nil) -> RomanNumeral {
        // Degree comes from the note letters, so Eb in C major is a third
        // (bIII) rather than being confused with a raised second.
        let degreeIndex = ((chord.root.letter.rawValue - key.tonic.letter.rawValue) % 7 + 7) % 7
        let degree = degreeIndex + 1
        let expected = key.mode.scaleOffsets[degreeIndex]
        let actual = key.tonic.pitchClass.distance(to: chord.root.pitchClass)
        var accidental = actual - expected
        if accidental > 6 { accidental -= 12 }
        if accidental < -6 { accidental += 12 }

        let keySet = extendedKeyPitchClasses(key)
        let isDiatonic = chord.pitchClasses.isSubset(of: keySet)

        // The leading tone in a minor key is expected, not an alteration.
        var displayAccidental = accidental
        if key.mode == .minor, degree == 7, accidental == 1,
           chord.quality.family == .diminished || chord.quality.family == .dominant {
            displayAccidental = 0
        }

        var base = numerals[degreeIndex]
        if isLowercase(chord.quality) { base = base.lowercased() }
        var symbol = accidentalPrefix(displayAccidental) + base + figure(for: chord.quality)
        if let bass = chord.bass {
            symbol += "/" + bass.name()
        }

        var function: HarmonicFunction = {
            guard isDiatonic || accidental == 0 else { return .chromatic }
            switch degree {
            case 1, 3, 6: return .tonic
            case 2, 4: return .subdominant
            case 5, 7: return .dominant
            default: return .chromatic
            }
        }()

        var explanation: String?
        var target: String?

        if !isDiatonic {
            if let secondary = secondaryFunction(chord, in: key, next: next) {
                symbol = secondary.symbol
                target = secondary.target
                explanation = secondary.explanation
                function = .dominant
            } else if degree == 2, accidental == -1, chord.quality.family == .major {
                explanation = "Neapolitan"
                function = .subdominant
            } else if let borrowed = borrowedSource(chord, in: key) {
                explanation = borrowed
                function = degree == 5 || degree == 7 ? .dominant
                    : (degree == 2 || degree == 4 ? .subdominant : .tonic)
            }
        }

        return RomanNumeral(symbol: symbol, degree: degree, accidental: accidental,
                            function: function, isDiatonic: isDiatonic,
                            explanation: explanation, target: target)
    }

    /// Recognise a chord that tonicises some other degree: `V7/ii`, `vii\u{00B0}7/V`,
    /// or a tritone substitute `subV7/I`.
    private static func secondaryFunction(_ chord: Chord, in key: Key, next: Chord?)
        -> (symbol: String, target: String, explanation: String)? {
        let rootPC = chord.root.pitchClass

        func diatonicNumeral(for pc: PitchClass) -> String? {
            guard let degree = key.scaleDegree(of: pc) else { return nil }
            let qualityID = key.diatonicQualityIDs[degree - 1]
            guard let quality = ChordDictionary.quality(id: qualityID) else { return nil }
            // Never call the tonic itself a target of tonicisation from nowhere.
            var numeral = numerals[degree - 1]
            if isLowercase(quality) { numeral = numeral.lowercased() }
            return numeral
        }

        let isDominantType = chord.quality.family == .dominant
            || (chord.quality.family == .major && chord.quality.id == "maj")

        if isDominantType {
            // A dominant resolves down a fifth.
            let resolution = PitchClass(rootPC.value + 5)
            if resolution != key.tonic.pitchClass || chord.quality.family == .dominant,
               let numeral = diatonicNumeral(for: resolution),
               resolution != rootPC {
                let figureText = figure(for: chord.quality)
                return ("V\(figureText)/\(numeral)", numeral,
                        "secondary dominant of \(numeral)")
            }
        }

        // The backdoor dominant. Bb7 in C is *also* the tritone substitute of
        // V7/vi, but when it sits a whole tone below the tonic and resolves up,
        // every chart in the world calls it bVII7, so check this first.
        if chord.quality.family == .dominant {
            let degreeIndex = ((chord.root.letter.rawValue - key.tonic.letter.rawValue) % 7 + 7) % 7
            let actual = key.tonic.pitchClass.distance(to: rootPC)
            if degreeIndex == 6, actual == 10 {
                let resolvesToTonic = next.map { $0.root.pitchClass == key.tonic.pitchClass } ?? true
                if resolvesToTonic {
                    return ("bVII\(figure(for: chord.quality))", "I", "backdoor dominant")
                }
            }
        }

        // Tritone substitute: shares a tritone with a dominant and resolves down
        // a semitone. Only claimed when the resolution is actually observed, or
        // when it points at the tonic — otherwise almost any altered dominant
        // can be argued into being a substitute for something.
        if chord.quality.family == .dominant {
            let resolution = PitchClass(rootPC.value + 11)
            let confirmed = next.map { $0.root.pitchClass == resolution } ?? false
            if let numeral = diatonicNumeral(for: resolution),
               confirmed || resolution == key.tonic.pitchClass {
                return ("subV\(figure(for: chord.quality))/\(numeral)", numeral,
                        "tritone substitute resolving to \(numeral)")
            }
        }

        // Secondary leading-tone chord resolves up a semitone.
        if chord.quality.family == .diminished {
            let resolution = PitchClass(rootPC.value + 1)
            if let numeral = diatonicNumeral(for: resolution), resolution != key.tonic.pitchClass {
                return ("vii\(figure(for: chord.quality))/\(numeral)", numeral,
                        "secondary leading-tone chord of \(numeral)")
            }
        }

        return nil
    }

    /// Modal interchange: the chord is diatonic to the parallel key, or to a
    /// common borrowed mode.
    private static func borrowedSource(_ chord: Chord, in key: Key) -> String? {
        let parallel = Key(tonic: key.tonic, mode: key.mode == .major ? .minor : .major)
        if chord.pitchClasses.isSubset(of: parallel.pitchClasses) {
            return "borrowed from the parallel \(parallel.mode.rawValue)"
        }
        for scaleID in ["dorian", "mixolydian", "lydian", "phrygian"] {
            guard let scale = ScaleLibrary.scale(id: scaleID) else { continue }
            if chord.pitchClasses.isSubset(of: scale.pitchClassSet(root: key.tonic.pitchClass)) {
                return "borrowed from \(key.tonic.name()) \(scale.name)"
            }
        }
        return nil
    }

    public static func analyze(_ chords: [Chord], in key: Key) -> [RomanNumeral] {
        chords.enumerated().map { index, chord in
            analyze(chord, in: key, resolvingTo: index + 1 < chords.count ? chords[index + 1] : nil)
        }
    }
}
