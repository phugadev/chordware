import Foundation

/// One possible reading of a set of notes, with how well it fits.
public struct ChordCandidate: Sendable, Hashable {
    public let chord: Chord
    /// 0...1, normalised against the best this quality could have scored.
    public let confidence: Double
    public let score: Double
    /// Template tones the player did not sound.
    public let missing: [Interval]
    /// Sounded pitch classes the template does not account for.
    public let extras: [PitchClass]

    public var isExact: Bool { missing.isEmpty && extras.isEmpty }
    public var symbol: String { chord.symbol() }
}

/// Turns a set of sounding notes into ranked chord readings.
///
/// The approach is template scoring rather than lookup: for each of the twelve
/// possible roots, every quality in the dictionary is scored against what was
/// actually played, and the results are ranked. That is what lets Chordware
/// show *both* `Am7` and `C6/A` with confidences instead of picking one and
/// hiding the ambiguity, which is genuinely useful information — those are the
/// same four notes and which one is "right" depends on context the notes alone
/// do not carry.
public enum ChordDetector {
    public struct Options: Sendable {
        /// Improves spelling and nudges ranking toward diatonic readings.
        public var key: Key?
        /// Allow readings whose root was not sounded (jazz rootless voicings).
        public var allowRootless: Bool
        public var maxCandidates: Int
        public var minConfidence: Double

        public init(key: Key? = nil,
                    allowRootless: Bool = true,
                    maxCandidates: Int = 6,
                    minConfidence: Double = 0.30) {
            self.key = key
            self.allowRootless = allowRootless
            self.maxCandidates = maxCandidates
            self.minConfidence = minConfidence
        }
    }

    // Scoring weights. Tuned against the fixtures in ChordFixtures.swift; if you
    // change one, run `make test` — several are load-bearing for close calls.
    private enum W {
        static let essentialPresent = 3.0
        static let optionalPresent = 1.0
        static let optionalMissing = -0.30
        static let colorPresent = 1.2
        static let extraPitchClass = -2.2
        static let rootPresent = 1.5
        static let rootAbsent = -2.5
        static let bassIsRoot = 2.0
        static let bassIsChordTone = 0.4
        static let bassIsForeign = -0.8
        static let complexity = -0.18
        static let keyDiatonicRoot = 0.6
        static let keyDiatonicQuality = 0.4
    }

    public static func detect(midiNotes: [Int], options: Options = Options()) -> [ChordCandidate] {
        guard !midiNotes.isEmpty else { return [] }
        let bass = midiNotes.min().map { PitchClass($0) }
        let pcs = Set(midiNotes.map { PitchClass($0) })
        return detect(pitchClasses: pcs, bass: bass, options: options)
    }

    public static func detect(pitchClasses pcs: Set<PitchClass>,
                              bass: PitchClass?,
                              options: Options = Options()) -> [ChordCandidate] {
        guard pcs.count >= 2 else { return [] }

        var candidates: [ChordCandidate] = []

        for rootValue in 0..<12 {
            let rootPC = PitchClass(rootValue)
            let rootSounded = pcs.contains(rootPC)
            if !rootSounded && !options.allowRootless { continue }

            for quality in ChordDictionary.all {
                guard let candidate = score(rootPC: rootPC,
                                            rootSounded: rootSounded,
                                            quality: quality,
                                            pcs: pcs,
                                            bass: bass,
                                            options: options) else { continue }
                candidates.append(candidate)
            }
        }

        // Rank, then drop duplicate spellings of the same sounding chord so the
        // list reads as distinct interpretations rather than near-identical rows.
        // Rank by confidence rather than raw score. Raw sums are biased toward
        // qualities that simply *require* more tones — a m7b5 collects four
        // essential-tone bonuses where a m6 collects three plus an optional —
        // which made C-Eb-G-A read as Am7b5/C even with C in the bass.
        // Normalising against what each quality could have scored removes that
        // bias, and makes the confidence shown in the UI agree with the order.
        var seen = Set<String>()
        return candidates
            .sorted { ($0.confidence, $0.score) > ($1.confidence, $1.score) }
            .filter { $0.confidence >= options.minConfidence }
            .filter { seen.insert($0.chord.symbol()).inserted }
            .prefix(options.maxCandidates)
            .map { $0 }
    }

    private static func score(rootPC: PitchClass,
                              rootSounded: Bool,
                              quality: ChordQuality,
                              pcs: Set<PitchClass>,
                              bass: PitchClass?,
                              options: Options) -> ChordCandidate? {
        var score = 0.0
        var maxScore = 0.0
        var missing: [Interval] = []

        for tone in quality.tones {
            let tonePC = PitchClass(rootPC.value + tone.interval.semitones)
            let present = pcs.contains(tonePC)
            switch tone.role {
            case .essential:
                maxScore += W.essentialPresent
                // A chord missing its own defining tone is a different chord.
                guard present else { return nil }
                score += W.essentialPresent
            case .optional:
                maxScore += W.optionalPresent
                if present { score += W.optionalPresent }
                else { score += W.optionalMissing; missing.append(tone.interval) }
            case .color:
                maxScore += W.colorPresent
                if present { score += W.colorPresent } else { missing.append(tone.interval) }
            }
        }

        // Pitch classes the template does not explain. The bass is excluded here
        // and charged separately, so a real slash chord like C/F# is read as C
        // major with a foreign bass rather than as a badly-fitting template.
        let templatePCs = Set(quality.pitchClassOffsets.map { PitchClass(rootPC.value + $0) })
        var extras = pcs.subtracting(templatePCs)
        let bassIsForeign = bass.map { !templatePCs.contains($0) } ?? false
        if let bass, bassIsForeign { extras.remove(bass) }
        score += Double(extras.count) * W.extraPitchClass

        maxScore += W.rootPresent
        score += rootSounded ? W.rootPresent : W.rootAbsent

        maxScore += W.bassIsRoot
        if let bass {
            if bass == rootPC { score += W.bassIsRoot }
            else if bassIsForeign { score += W.bassIsForeign }
            else { score += W.bassIsChordTone }
        }

        let complexityPenalty = Double(quality.cardinality) * W.complexity
        score += complexityPenalty
        maxScore += complexityPenalty

        if let key = options.key {
            maxScore += W.keyDiatonicRoot + W.keyDiatonicQuality
            if key.contains(rootPC) { score += W.keyDiatonicRoot }
            if let degree = key.scaleDegree(of: rootPC),
               key.diatonicQualityIDs[degree - 1] == quality.id {
                score += W.keyDiatonicQuality
            }
        }

        guard maxScore > 0 else { return nil }
        let confidence = max(0.0, min(1.0, score / maxScore))

        let root = Chord.bestRootSpelling(for: rootPC, quality: quality, key: options.key)
        let bassNote: SpelledNote? = bass.flatMap { b -> SpelledNote? in
            guard b != rootPC else { return nil }
            // Spell the bass as a chord tone when it is one, so C/E reads E and
            // not Fb, and fall back to the key's accidental preference otherwise.
            if let tone = quality.tones.first(where: {
                PitchClass(rootPC.value + $0.interval.semitones) == b
            }) {
                return root.spelled(degree: tone.interval.degree, semitones: tone.interval.semitones)
            }
            return SpelledNote.natural(b, preferFlats: options.key?.preferFlats ?? (root.alteration < 0))
        }

        return ChordCandidate(
            chord: Chord(root: root, quality: quality, bass: bassNote),
            confidence: confidence,
            score: score,
            missing: missing,
            extras: Array(extras).sorted()
        )
    }

    /// Best single reading, or `nil` when the notes do not form a chord.
    public static func best(midiNotes: [Int], options: Options = Options()) -> ChordCandidate? {
        detect(midiNotes: midiNotes, options: options).first
    }

    /// Name a two-note pairing, which is an interval rather than a chord.
    public static func describeDyad(midiNotes: [Int]) -> String? {
        let pcs = Set(midiNotes.map { PitchClass($0) })
        guard pcs.count == 2, let low = midiNotes.min(), let high = midiNotes.max() else { return nil }
        let semitones = (high - low) % 12
        let names = ["unison", "minor 2nd", "major 2nd", "minor 3rd", "major 3rd",
                     "perfect 4th", "tritone", "perfect 5th", "minor 6th",
                     "major 6th", "minor 7th", "major 7th"]
        return names[semitones]
    }
}
