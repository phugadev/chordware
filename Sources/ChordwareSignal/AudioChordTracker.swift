import ChordwareCore
import Foundation

/// Matches a chroma vector against chord templates, with enough smoothing and
/// hysteresis that the readout does not strobe.
public final class AudioChordTracker {
    public struct Configuration: Sendable {
        /// Exponential smoothing over incoming frames; lower is steadier.
        public var smoothing: Double
        /// How far a challenger must beat the incumbent before it takes over.
        public var switchMargin: Double
        /// Frames a challenger must hold that lead for.
        public var dwellFrames: Int
        /// Below this the input is treated as silence rather than a chord.
        public var minimumEnergy: Double
        /// Below this similarity nothing is reported at all.
        public var minimumSimilarity: Double

        public init(smoothing: Double = 0.30, switchMargin: Double = 0.03,
                    dwellFrames: Int = 2, minimumEnergy: Double = 0.08,
                    minimumSimilarity: Double = 0.60) {
            self.smoothing = smoothing
            self.switchMargin = switchMargin
            self.dwellFrames = dwellFrames
            self.minimumEnergy = minimumEnergy
            self.minimumSimilarity = minimumSimilarity
        }
    }

    /// Qualities worth attempting from audio.
    ///
    /// Deliberately narrower than the full dictionary: a recording cannot
    /// reliably tell a 13th from a 6/9 with a different bass, so offering
    /// those would be confident nonsense. Triads, sixths and sevenths are what
    /// chroma can actually support.
    public static let audioQualityIDs = [
        "maj", "min", "dim", "aug", "sus4", "sus2",
        "7", "maj7", "m7", "mMaj7", "m7b5", "dim7", "6", "m6",
    ]

    public private(set) var chord: Chord?
    public private(set) var confidence: Double = 0
    public private(set) var smoothed = [Double](repeating: 0, count: 12)

    public var configuration: Configuration
    public var key: Key?

    private struct Template {
        let chord: Chord
        let vector: [Double]
        /// Pitch classes the chord cannot do without. The fifth is excluded on
        /// purpose: it is optional in the dictionary and weak in real audio.
        let essential: [Int]
    }

    private var templates: [Template] = []
    /// Recent bass estimates, so one bad frame cannot move the reading.
    private var bassHistory: [PitchClass?] = []
    private var challenger: Chord?
    private var challengerFrames = 0
    private var hasSmoothed = false

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        buildTemplates()
    }

    private func buildTemplates() {
        var built: [Template] = []
        for id in Self.audioQualityIDs {
            guard let quality = ChordDictionary.quality(id: id) else { continue }
            for rootValue in 0..<12 {
                var vector = [Double](repeating: 0, count: 12)
                for tone in quality.tones {
                    let pc = PitchClass(rootValue + tone.interval.semitones).value
                    // The fifth carries least identity, so let it matter least.
                    let weight: Double
                    switch tone.role {
                    case .essential: weight = 1.0
                    case .optional: weight = 0.7
                    case .color: weight = 0.6
                    }
                    vector[pc] = max(vector[pc], weight)
                }
                let essential = quality.tones
                    .filter { $0.role == .essential }
                    .map { PitchClass(rootValue + $0.interval.semitones).value }
                let root = Chord.bestRootSpelling(for: PitchClass(rootValue), quality: quality, key: key)
                built.append(Template(chord: Chord(root: root, quality: quality),
                                      vector: vector, essential: essential))
            }
        }
        templates = built
    }

    public func reset() {
        chord = nil
        confidence = 0
        smoothed = [Double](repeating: 0, count: 12)
        hasSmoothed = false
        challenger = nil
        challengerFrames = 0
        bassHistory.removeAll()
    }

    /// The steadiest recent bass estimate.
    private var stableBass: PitchClass? {
        var counts: [PitchClass: Int] = [:]
        for case let bass? in bassHistory { counts[bass, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key
    }

    /// Feed one chroma frame. Returns the chord when it changes, else nil.
    @discardableResult
    public func observe(_ frame: ChromaFrame) -> Chord? {
        guard frame.values.count == 12 else { return nil }

        if hasSmoothed {
            let a = configuration.smoothing
            for i in 0..<12 { smoothed[i] = smoothed[i] * (1 - a) + frame.values[i] * a }
        } else {
            smoothed = frame.values
            hasSmoothed = true
        }
        bassHistory.append(frame.bass)
        if bassHistory.count > 5 { bassHistory.removeFirst() }

        let energy = smoothed.reduce(0, +) / 12.0
        guard energy >= configuration.minimumEnergy else {
            let had = chord != nil
            chord = nil
            confidence = 0
            challenger = nil
            challengerFrames = 0
            return had ? nil : nil
        }

        let ranked = rank(ChromaFrame(values: smoothed, bass: stableBass))
        guard let best = ranked.first, best.score >= configuration.minimumSimilarity else {
            return nil
        }

        // Hysteresis: an incumbent keeps the display until a challenger holds a
        // real lead for a few frames. Without this the readout flickers between
        // relative major and minor on every frame.
        if chord == best.chord {
            confidence = min(1.0, best.score)
            challenger = nil
            challengerFrames = 0
            return nil
        }

        let incumbentScore = chord.flatMap { current in
            ranked.first { $0.chord == current }?.score
        } ?? 0

        guard best.score > incumbentScore + configuration.switchMargin else {
            challenger = nil
            challengerFrames = 0
            return nil
        }

        if challenger == best.chord {
            challengerFrames += 1
        } else {
            challenger = best.chord
            challengerFrames = 1
        }

        guard challengerFrames >= configuration.dwellFrames else { return nil }
        chord = best.chord
        // The bass bonus can push a score past 1; confidence is shown to people.
        confidence = min(1.0, best.score)
        challenger = nil
        challengerFrames = 0
        return chord
    }

    /// Templates scored against a chroma frame, best first.
    ///
    /// Cosine similarity alone always prefers the richer template, because a
    /// seventh chord explains more of the spectrum than a triad does — even
    /// when the "seventh" is only the overtones of the other notes. Two
    /// corrections fix that without an arbitrary complexity constant:
    ///
    /// - *support*: the geometric mean of the chroma at the template's
    ///   essential tones. A geometric mean collapses if any single member is
    ///   weak, so a chord may not claim a tone that is barely present.
    /// - *bass*: chroma cannot distinguish Dm7 from F6, since they are the same
    ///   four pitch classes. The lowest fundamental decides.
    public func rank(_ frame: ChromaFrame, limit: Int = 5) -> [(chord: Chord, score: Double)] {
        let chroma = frame.values
        let norm = (chroma.reduce(0) { $0 + $1 * $1 }).squareRoot()
        let peak = chroma.max() ?? 0
        guard norm > 0, peak > 0 else { return [] }

        return templates
            .map { template -> (Chord, Double) in
                var dot = 0.0, templateNorm = 0.0
                for i in 0..<12 {
                    dot += chroma[i] * template.vector[i]
                    templateNorm += template.vector[i] * template.vector[i]
                }
                let denominator = norm * templateNorm.squareRoot()
                var score = denominator > 0 ? dot / denominator : 0

                if !template.essential.isEmpty {
                    var product = 1.0
                    for pc in template.essential {
                        product *= max(chroma[pc] / peak, 0.001)
                    }
                    score *= pow(product, 1.0 / Double(template.essential.count))
                }

                if let bass = frame.bass {
                    let rootPC = template.chord.root.pitchClass
                    if bass == rootPC {
                        score *= 1.10
                    } else if template.vector[bass.value] == 0 {
                        // The bass is not even a chord tone.
                        score *= 0.88
                    }
                }
                return (template.chord, score)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { (chord: $0.0, score: $0.1) }
    }
}
