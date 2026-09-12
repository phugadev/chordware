import Foundation

public struct KeyEstimate: Sendable, Hashable {
    public let key: Key
    /// 0...1. How far ahead of the runner-up this key is, not an absolute truth claim.
    public let confidence: Double
    public let runnerUp: Key?

    public init(key: Key, confidence: Double, runnerUp: Key?) {
        self.key = key
        self.confidence = confidence
        self.runnerUp = runnerUp
    }
}

/// Estimates the tonal centre from what has been played recently.
///
/// Uses Krumhansl–Kessler key profiles correlated against a time-decayed
/// pitch-class histogram. The decay is the important part for live use: a
/// modulation should move the estimate within a few bars rather than being
/// outvoted forever by everything played before it.
public final class KeyEstimator {
    /// Krumhansl–Kessler probe-tone profiles, rated stability of each scale
    /// degree against a tonic.
    private static let majorProfile: [Double] = [
        6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88,
    ]
    private static let minorProfile: [Double] = [
        6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17,
    ]

    /// Seconds for an observation's influence to halve.
    public var halfLife: Double
    /// Below this, `estimate` reports nil rather than guessing from noise.
    public var minimumObservations: Double
    /// How many different chord roots must have been heard recently before a
    /// key is named at all.
    ///
    /// A key is a property of a passage, not of a chord. One triad used to
    /// clear `minimumObservations` on its own -- three notes plus a root bonus
    /// is 4.5 -- so the first chord you played named a key at 99% confidence,
    /// and every chord after it renamed it. C major alone is equally at home in
    /// C, F, G, A minor and E minor; there is nothing to be confident about.
    public var minimumDistinctRoots: Int
    /// How far a challenger must beat the standing key to replace it.
    ///
    /// Neighbouring keys score within about a tenth of each other, so without
    /// this the estimate flickers between relatives on every chord.
    public var switchMargin: Double

    private var weights = [Double](repeating: 0, count: 12)
    /// Evidence that a chord rooted on each pitch class had a major / minor
    /// third. The profiles alone cannot see this, and it is the strongest
    /// single clue about mode that a progression offers.
    private var majorThird = [Double](repeating: 0, count: 12)
    private var minorThird = [Double](repeating: 0, count: 12)
    /// Weight of each pitch class seen as a chord *root*, decayed like the
    /// rest. Counting distinct roots is how "enough has been played to call
    /// this a key" is decided.
    private var rootObservations = [Double](repeating: 0, count: 12)
    /// The key currently being reported, so a challenger has to earn the swap.
    private var established: Key?
    private var lastUpdate: Double?
    private var totalWeight: Double = 0

    public init(halfLife: Double = 12.0, minimumObservations: Double = 6.0,
                minimumDistinctRoots: Int = 3, switchMargin: Double = 0.04) {
        self.halfLife = halfLife
        self.minimumObservations = minimumObservations
        self.minimumDistinctRoots = minimumDistinctRoots
        self.switchMargin = switchMargin
    }

    public func reset() {
        weights = [Double](repeating: 0, count: 12)
        majorThird = [Double](repeating: 0, count: 12)
        minorThird = [Double](repeating: 0, count: 12)
        rootObservations = [Double](repeating: 0, count: 12)
        established = nil
        lastUpdate = nil
        totalWeight = 0
    }

    private func decay(to time: Double) {
        guard let last = lastUpdate else { lastUpdate = time; return }
        let elapsed = max(0, time - last)
        guard elapsed > 0 else { return }
        let factor = pow(0.5, elapsed / halfLife)
        for i in 0..<12 {
            weights[i] *= factor
            majorThird[i] *= factor
            minorThird[i] *= factor
            rootObservations[i] *= factor
        }
        totalWeight *= factor
        lastUpdate = time
    }

    /// Record sounding pitch classes. `weight` is usually note duration in
    /// seconds, which is what the profiles were derived against.
    public func observe(pitchClasses: [PitchClass], weight: Double = 1.0, at time: Double) {
        decay(to: time)
        for pc in pitchClasses {
            weights[pc.value] += weight
            totalWeight += weight
        }
    }

    /// Record a detected chord. The root and bass carry more tonal weight than
    /// inner voices, which is what separates a passing sonority from a cadence.
    public func observe(chord: Chord, weight: Double = 1.0, at time: Double) {
        decay(to: time)
        for pc in chord.pitchClasses {
            weights[pc.value] += weight
            totalWeight += weight
        }
        weights[chord.root.pitchClass.value] += weight * 1.5
        totalWeight += weight * 1.5
        if let bass = chord.bass {
            weights[bass.pitchClass.value] += weight * 0.5
            totalWeight += weight * 0.5
        }

        let root = chord.root.pitchClass.value
        rootObservations[root] += weight
        if chord.pitchClasses.contains(PitchClass(root + 4)) { majorThird[root] += weight }
        if chord.pitchClasses.contains(PitchClass(root + 3)) { minorThird[root] += weight }
    }

    /// Nudge a pitch class without implying a whole chord, used for the
    /// positional emphasis that first and last chords carry.
    public func emphasise(_ pc: PitchClass, weight: Double, at time: Double) {
        decay(to: time)
        weights[pc.value] += weight
        totalWeight += weight
    }

    /// Roots still carrying real weight. Decay is doing the work here: a root
    /// played a minute ago has faded out and no longer counts towards "enough
    /// has been played", which is why a long rest starts the question over.
    private var distinctRoots: Int {
        rootObservations.count { $0 >= 0.5 }
    }

    public var estimate: KeyEstimate? {
        guard totalWeight >= minimumObservations else { return nil }
        // The variety requirement is about *chords*: one chord is weak evidence
        // for a key. Raw pitch classes carry no roots and are a different kind
        // of evidence -- a chroma frame or an explicit set of notes -- so they
        // are judged on weight alone, as before.
        let sawChords = rootObservations.contains { $0 > 0 }
        guard !sawChords || distinctRoots >= minimumDistinctRoots else { return nil }
        let ranked = adjustForMode(Self.rank(weights: weights))
        guard let best = ranked.first else { return nil }

        // Hold the standing key unless the challenger clearly beats it.
        if let standing = established,
           let incumbent = ranked.first(where: { $0.0 == standing }),
           best.1 - incumbent.1 < switchMargin {
            return KeyEstimate(key: standing, confidence: Self.confidence(from: ranked),
                               runnerUp: best.0 == standing ? ranked.dropFirst().first?.0 : best.0)
        }
        established = best.0
        return KeyEstimate(key: best.0, confidence: Self.confidence(from: ranked),
                           runnerUp: ranked.dropFirst().first?.0)
    }

    private enum ExpectedThird { case major, minor, either }

    /// The third built on each scale degree, in semitones above the tonic.
    ///
    /// A root that appears in neither table is borrowed and carries no
    /// expectation at all: punishing it would read every modal-interchange
    /// chord as a modulation.
    private static let majorDegrees: [Int: ExpectedThird] = [
        0: .major, 2: .minor, 4: .minor, 5: .major, 7: .major, 9: .minor, 11: .minor,
    ]
    /// Minor keys borrow their dominant from the harmonic form more often than
    /// not, so degree 7 accepts either quality.
    private static let minorDegrees: [Int: ExpectedThird] = [
        0: .minor, 2: .minor, 3: .major, 5: .minor,
        7: .either, 8: .major, 10: .major, 11: .minor,
    ]

    /// Re-rank by whether the chords played are the chords this key is made of.
    ///
    /// Pitch-class profiles count notes, so they cannot tell `Dm G C` from the
    /// key of G: D is the most common note in it either way, and Krumhansl
    /// reads a prominent second-most-common note as the dominant. What settles
    /// it is that the D chord is *minor*, and G major's second degree is a D
    /// major chord. Comparing the quality of the chord on every degree - not
    /// only the tonic - is the evidence a progression actually offers.
    ///
    /// It also keeps the case this replaces: `Cmaj7 Ab Bb7 Cmaj7` is C major
    /// with a borrowed bVI and bVII, and the natural third on the tonic still
    /// outweighs the flat-side material, because the tonic counts double.
    private func adjustForMode(_ ranked: [(Key, Double)]) -> [(Key, Double)] {
        let evidence = zip(majorThird, minorThird).reduce(0.0) { $0 + $1.0 + $1.1 }
        guard totalWeight > 0, evidence > 0 else { return ranked }
        return ranked.map { key, score in
            let tonic = key.tonic.pitchClass.value
            let degrees = key.mode == .major ? Self.majorDegrees : Self.minorDegrees
            var agreement = 0.0
            for pc in 0..<12 {
                let major = majorThird[pc], minor = minorThird[pc]
                guard major + minor > 0 else { continue }
                guard let expected = degrees[(pc - tonic + 12) % 12] else { continue }
                // The quality of the tonic chord is the strongest single clue a
                // progression gives, so it counts for two.
                let emphasis = pc == tonic ? 2.0 : 1.0
                switch expected {
                case .major: agreement += emphasis * (major - minor)
                case .minor: agreement += emphasis * (minor - major)
                case .either: agreement += emphasis * (major + minor) * 0.5
                }
            }
            return (key, score + (agreement / evidence) * Self.qualityWeight)
        }.sorted { $0.1 > $1.1 }
    }

    /// How far chord quality can move a key against the profile correlation.
    /// Correlations for neighbouring keys sit within about 0.1 of each other,
    /// so this is the same order of magnitude as the thing it is arguing with.
    private static let qualityWeight = 0.30

    /// All 24 keys scored against a pitch-class weight vector, best first.
    public static func rank(weights: [Double]) -> [(Key, Double)] {
        guard weights.count == 12, weights.contains(where: { $0 > 0 }) else { return [] }
        var scored: [(Key, Double)] = []
        for tonic in 0..<12 {
            let rotated = (0..<12).map { weights[(tonic + $0) % 12] }
            scored.append((Key.allKeys[tonic], correlation(rotated, majorProfile)))
            scored.append((Key.allKeys[12 + tonic], correlation(rotated, minorProfile)))
        }
        return scored.sorted { $0.1 > $1.1 }
    }

    private static func correlation(_ a: [Double], _ b: [Double]) -> Double {
        let n = Double(a.count)
        let meanA = a.reduce(0, +) / n
        let meanB = b.reduce(0, +) / n
        var num = 0.0, denA = 0.0, denB = 0.0
        for i in 0..<a.count {
            let da = a[i] - meanA, db = b[i] - meanB
            num += da * db
            denA += da * da
            denB += db * db
        }
        let den = (denA * denB).squareRoot()
        return den == 0 ? 0 : num / den
    }

    /// One-shot estimate for a finished passage, used by the CLI and by
    /// progression analysis where there is no live timeline. Runs through the
    /// same instance logic so live and offline estimates cannot diverge.
    public static func estimate(chords: [Chord]) -> KeyEstimate? {
        guard !chords.isEmpty else { return nil }
        let estimator = KeyEstimator(halfLife: .infinity, minimumObservations: 0)
        for chord in chords { estimator.observe(chord: chord, at: 0) }
        // Passages tend to *begin* on the tonic, and to end on it only when the
        // last chord is one a passage can rest on. Weighting it unconditionally
        // reads `Cmaj7 Am7 Dm7 G7`, an ordinary turnaround in C, as G major --
        // and a phrase ending on vii-diminished as the key a step below, since
        // nothing else is pulling against it.
        let unrestful: Set<ChordFamily> = [.dominant, .diminished, .augmented, .suspended]
        if let first = chords.first { estimator.emphasise(first.root.pitchClass, weight: 1.0, at: 0) }
        if let last = chords.last, !unrestful.contains(last.quality.family) {
            estimator.emphasise(last.root.pitchClass, weight: 1.5, at: 0)
        }
        return estimator.estimate
    }

    public static func estimate(pitchClasses: [PitchClass]) -> KeyEstimate? {
        guard !pitchClasses.isEmpty else { return nil }
        let estimator = KeyEstimator(halfLife: .infinity, minimumObservations: 0)
        estimator.observe(pitchClasses: pitchClasses, at: 0)
        return estimator.estimate
    }

    /// Turn 24 raw correlations into a probability for the winner.
    ///
    /// A plain margin reads far too low: profile correlations for neighbouring
    /// keys sit close together, so a textbook ii-V-I would show almost no
    /// confidence. A softmax spreads them into something that means what a
    /// reader thinks it means, while still refusing to be confident about a
    /// bare scale that fits a major key and its relative minor equally.
    private static func confidence(from ranked: [(Key, Double)]) -> Double {
        guard let best = ranked.first else { return 0 }
        let temperature = 0.045
        let total = ranked.reduce(0.0) { $0 + exp(($1.1 - best.1) / temperature) }
        return total > 0 ? min(1.0, 1.0 / total) : 0
    }
}
