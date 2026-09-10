import Accelerate
import ChordwareCore
import Foundation

/// Turns a stream of audio samples into a twelve-bin pitch-class profile.
///
/// The naive version of this — FFT, fold every bin onto its pitch class — calls
/// almost every major triad a 6/9, because the third harmonic of the root lands
/// a fifth up and the fifth harmonic lands a major third up, so the overtones
/// of three notes look like six. This uses harmonic summation instead: each
/// candidate fundamental is scored by how much energy sits at *its* harmonic
/// series, which lets a real note outvote another note's overtone.
/// A chroma vector plus the lowest fundamental the extractor was confident in.
///
/// The bass matters because chroma alone cannot separate chords that share a
/// pitch-class set: Dm7 and F6 are the same four notes, and only the bass says
/// which one is being played.
public struct ChromaFrame: Sendable, Equatable {
    public var values: [Double]
    public var bass: PitchClass?
    /// MIDI notes the extractor believes are sounding, strongest first. Lets
    /// the island light up a keyboard from audio the same way it does from MIDI.
    public var notes: [Int] = []
    /// Mean energy, used to tell a chord from silence.
    public var energy: Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }

    public init(values: [Double], bass: PitchClass? = nil, notes: [Int] = []) {
        self.values = values
        self.bass = bass
        self.notes = notes
    }

    public static let silent = ChromaFrame(values: [Double](repeating: 0, count: 12))
}

public final class ChromaExtractor {
    public struct Configuration: Sendable {
        public var sampleRate: Double
        /// 16384 at 44.1 kHz gives 2.7 Hz bins, which is what it takes to
        /// separate semitones down in the bass where the bass note lives. The
        /// window is long (371 ms) but the hop is short, so the readout still
        /// updates every 46 ms.
        public var frameSize: Int
        public var hopSize: Int
        public var lowNote: Int
        public var highNote: Int
        public var harmonics: Int
        public var harmonicDecay: Double

        public init(sampleRate: Double = 44100, frameSize: Int = 16384, hopSize: Int = 2048,
                    lowNote: Int = 36, highNote: Int = 96,
                    harmonics: Int = 6, harmonicDecay: Double = 0.6) {
            self.sampleRate = sampleRate
            self.frameSize = frameSize
            self.hopSize = hopSize
            self.lowNote = lowNote
            self.highNote = highNote
            self.harmonics = harmonics
            self.harmonicDecay = harmonicDecay
        }
    }

    public let configuration: Configuration
    private let fft: vDSP.FFT<DSPSplitComplex>
    private let window: [Float]
    private let log2n: vDSP_Length
    /// Which semitone each spectrum bin belongs to, or -1 for none.
    private let binNote: [Int]
    private let noteCount: Int
    /// Harmonic offsets in semitones, rounded to the nearest note.
    private let harmonicOffsets: [(offset: Int, weight: Double)]

    private var pending: [Float] = []

    /// Upper bound on notes pulled out of one frame. A dense voicing spread
    /// over five octaves is still well under this.
    private static let maxVoices = 24
    /// Stop subtracting once the remaining peak is this fraction of the first.
    private static let residualFloor = 0.06
    /// A voice must be at least this strong to be considered the bass.
    private static let bassSupport = 0.35
    /// A candidate fundamental needs at least this share of the peak at its own
    /// pitch before its harmonic series is even considered.
    private static let minimumFundamental = 0.10

    public init?(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        let n = configuration.frameSize
        guard n > 0, (n & (n - 1)) == 0 else { return nil }
        log2n = vDSP_Length(log2(Double(n)))
        guard let fft = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self) else {
            return nil
        }
        self.fft = fft
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                             count: n, isHalfWindow: false)

        let binWidth = configuration.sampleRate / Double(n)
        let binCount = n / 2
        noteCount = configuration.highNote - configuration.lowNote + 1

        // Assign every bin to exactly one semitone.
        //
        // Computing a bin *range* per semitone instead lets neighbouring bands
        // overlap, because rounding outward adds a bin at each end. B3 and C4
        // then share bins, C4's peak leaks into B3, and the extractor invents a
        // bass note a semitone below the real one.
        var map = [Int](repeating: -1, count: binCount)
        for bin in 1..<binCount {
            let frequency = Double(bin) * binWidth
            let exact = 69.0 + 12.0 * log2(frequency / 440.0)
            let note = Int(exact.rounded())
            guard note >= configuration.lowNote, note <= configuration.highNote else { continue }
            map[bin] = note - configuration.lowNote
        }
        binNote = map

        harmonicOffsets = (1...max(1, configuration.harmonics)).map { h in
            // The h-th harmonic sits 12*log2(h) semitones above the fundamental.
            (Int((12.0 * log2(Double(h))).rounded()), pow(configuration.harmonicDecay, Double(h - 1)))
        }
    }

    public func reset() { pending.removeAll(keepingCapacity: true) }

    /// Feed samples; returns a chroma frame for every complete hop.
    public func process(samples: [Float]) -> [ChromaFrame] {
        pending.append(contentsOf: samples)
        var results: [ChromaFrame] = []
        let n = configuration.frameSize
        while pending.count >= n {
            results.append(chroma(frame: Array(pending[0..<n])))
            pending.removeFirst(configuration.hopSize)
        }
        // Do not let a silent or stalled input grow the buffer without bound.
        if pending.count > n * 4 { pending.removeFirst(pending.count - n) }
        return results
    }

    /// One frame of samples to one normalised chroma frame.
    public func chroma(frame: [Float]) -> ChromaFrame {
        let magnitudes = spectrum(frame: frame)
        guard !magnitudes.isEmpty else { return .silent }

        // Energy per semitone: the strongest bin belonging to it.
        var semitone = [Double](repeating: 0, count: noteCount)
        for bin in 1..<min(magnitudes.count, binNote.count) {
            let index = binNote[bin]
            guard index >= 0 else { continue }
            semitone[index] = max(semitone[index], Double(magnitudes[bin]))
        }

        // Subtract the noise floor so quiet broadband hiss does not colour the
        // profile; a chord is peaks, not an average.
        let sorted = semitone.sorted()
        let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        for index in semitone.indices { semitone[index] = max(0, semitone[index] - median) }

        // Iterative harmonic subtraction.
        //
        // Summing each note's harmonic series is not enough on its own: a C
        // major triad puts real energy on B, because E's third harmonic and
        // G's fifth harmonic both land there, and template matching then
        // prefers Cmaj7 over C because it explains more of the spectrum. So
        // take the strongest fundamental, *remove* its overtones from the
        // residual, and repeat — a note only keeps energy the notes above it
        // cannot account for.
        var residual = semitone
        var chroma = [Double](repeating: 0, count: 12)
        var voices: [(index: Int, score: Double)] = []
        let initialPeak = residual.max() ?? 0
        guard initialPeak > 0 else { return .silent }

        for _ in 0..<Self.maxVoices {
            var bestIndex = -1
            var bestScore = 0.0
            for index in residual.indices {
                // A candidate must have real energy at its *own* pitch. Scoring
                // purely by harmonic sum favours low notes, because a low
                // fundamental's series happens to cover many of the partials
                // that the actual notes produced — which is how a C major triad
                // ends up reporting a phantom B two octaves down.
                guard residual[index] >= initialPeak * Self.minimumFundamental else { continue }
                var score = 0.0
                for (offset, weight) in harmonicOffsets {
                    let target = index + offset
                    guard target < residual.count else { break }
                    score += weight * residual[target]
                }
                if score > bestScore { bestScore = score; bestIndex = index }
            }
            guard bestIndex >= 0, bestScore > initialPeak * Self.residualFloor else { break }

            let amplitude = residual[bestIndex]
            guard amplitude > 0 else { break }

            let note = configuration.lowNote + bestIndex
            // Credit the note with the energy measured at its own pitch, not
            // with its harmonic sum: the sum is inflated for low notes and
            // makes a triad's fifth outrank its root.
            chroma[PitchClass(note).value] += amplitude
            voices.append((bestIndex, amplitude))

            residual[bestIndex] = 0
            for (offset, weight) in harmonicOffsets where offset > 0 {
                let target = bestIndex + offset
                guard target < residual.count else { break }
                residual[target] = max(0, residual[target] - weight * amplitude)
            }
        }

        let peak = chroma.max() ?? 0
        guard peak > 0 else { return .silent }

        // Lowest voice that carried real weight. A quiet rumble below the
        // music must not be mistaken for the bass line.
        let strongest = voices.map(\.score).max() ?? 0
        let bassIndex = voices
            .filter { $0.score >= strongest * Self.bassSupport }
            .map(\.index)
            .min()
        let bass = bassIndex.map { PitchClass(configuration.lowNote + $0) }

        let strongVoices = voices
            .filter { $0.score >= strongest * Self.bassSupport }
            .sorted { $0.score > $1.score }
            .map { configuration.lowNote + $0.index }

        return ChromaFrame(values: chroma.map { $0 / peak }, bass: bass, notes: strongVoices)
    }

    /// Windowed magnitude spectrum, first half only.
    private func spectrum(frame: [Float]) -> [Float] {
        let n = configuration.frameSize
        let half = n / 2
        var windowed = [Float](repeating: 0, count: n)
        vDSP.multiply(frame, window, result: &windowed)

        var realIn = [Float](repeating: 0, count: half)
        var imagIn = [Float](repeating: 0, count: half)
        var realOut = [Float](repeating: 0, count: half)
        var imagOut = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)

        realIn.withUnsafeMutableBufferPointer { realInPtr in
            imagIn.withUnsafeMutableBufferPointer { imagInPtr in
                var input = DSPSplitComplex(realp: realInPtr.baseAddress!,
                                            imagp: imagInPtr.baseAddress!)
                // Real-to-complex packing: even samples become the real part,
                // odd samples the imaginary part.
                windowed.withUnsafeBufferPointer { windowedPtr in
                    windowedPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &input, 1, vDSP_Length(half))
                    }
                }
                realOut.withUnsafeMutableBufferPointer { realOutPtr in
                    imagOut.withUnsafeMutableBufferPointer { imagOutPtr in
                        var output = DSPSplitComplex(realp: realOutPtr.baseAddress!,
                                                     imagp: imagOutPtr.baseAddress!)
                        fft.forward(input: input, output: &output)
                        magnitudes.withUnsafeMutableBufferPointer { magPtr in
                            vDSP_zvabs(&output, 1, magPtr.baseAddress!, 1, vDSP_Length(half))
                        }
                    }
                }
            }
        }
        return magnitudes
    }
}
