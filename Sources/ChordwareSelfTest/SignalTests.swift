import ChordwareCore
import ChordwareSignal
import Foundation

/// A note with a plausible overtone series, so the tests exercise the harmonic
/// summation rather than a bare sine the naive approach would also pass.
private func tone(midi: Int, sampleRate: Double, count: Int, harmonics: Int = 6) -> [Float] {
    let f0 = MIDINote.frequency(midi)
    var samples = [Float](repeating: 0, count: count)
    for h in 1...harmonics {
        let frequency = f0 * Double(h)
        guard frequency < sampleRate / 2 else { break }
        let amplitude = 1.0 / Double(h)
        let step = 2.0 * Double.pi * frequency / sampleRate
        for i in 0..<count { samples[i] += Float(amplitude * sin(step * Double(i))) }
    }
    let peak = samples.map { abs($0) }.max() ?? 1
    return peak > 0 ? samples.map { $0 / peak } : samples
}

private func mix(_ parts: [[Float]]) -> [Float] {
    guard let count = parts.first?.count else { return [] }
    var out = [Float](repeating: 0, count: count)
    for part in parts { for i in 0..<count { out[i] += part[i] } }
    let peak = out.map { abs($0) }.max() ?? 1
    return peak > 0 ? out.map { $0 / peak } : out
}

func runSignalTests(_ t: Harness) {
    let sampleRate = 44100.0
    guard let extractor = ChromaExtractor(
        configuration: .init(sampleRate: sampleRate)
    ) else {
        t.suite("Chroma") { t.test("extractor builds") { t.check(false, "could not build extractor") } }
        return
    }
    let frameSize = extractor.configuration.frameSize

    t.suite("Chroma extraction") {
        t.test("a single note peaks on its own pitch class") {
            let a4 = tone(midi: 69, sampleRate: sampleRate, count: frameSize)
            let chroma = extractor.chroma(frame: a4).values
            let peak = chroma.enumerated().max { $0.element < $1.element }?.offset
            t.equal(peak, 9, "A440 peaks on A")
        }

        t.test("harmonics do not masquerade as extra notes") {
            // A single C with six harmonics contains energy at G (3rd harmonic)
            // and E (5th). A naive fold calls that a C6/9; harmonic summation
            // should keep C clearly on top.
            let c3 = tone(midi: 48, sampleRate: sampleRate, count: frameSize, harmonics: 6)
            let chroma = extractor.chroma(frame: c3).values
            let g = chroma[7], e = chroma[4], c = chroma[0]
            t.check(c > g * 1.5, "C beats its own fifth harmonic (C=\(c), G=\(g))")
            t.check(c > e * 1.5, "C beats its own third harmonic (C=\(c), E=\(e))")
        }

        t.test("a triad shows three peaks") {
            let triad = mix([
                tone(midi: 60, sampleRate: sampleRate, count: frameSize),
                tone(midi: 64, sampleRate: sampleRate, count: frameSize),
                tone(midi: 67, sampleRate: sampleRate, count: frameSize),
            ])
            let chroma = extractor.chroma(frame: triad).values
            let ranked = chroma.enumerated().sorted { $0.element > $1.element }.prefix(3)
            t.equal(Set(ranked.map(\.offset)), Set([0, 4, 7]), "C E G are the top three")
        }

        t.test("silence produces no chroma") {
            let silence = [Float](repeating: 0, count: frameSize)
            t.check(extractor.chroma(frame: silence).values.allSatisfy { $0 == 0 }, "silent frame is empty")
        }

        t.test("streaming yields one frame per hop") {
            extractor.reset()
            let block = tone(midi: 60, sampleRate: sampleRate, count: frameSize)
            let first = extractor.process(samples: block)
            t.equal(first.count, 1, "one full frame in, one chroma out")
            let second = extractor.process(samples: Array(block[0..<extractor.configuration.hopSize]))
            t.equal(second.count, 1, "another hop yields another frame")
            extractor.reset()
        }
    }

    t.suite("Audio chord tracking") {
        func detect(_ midiNotes: [Int], frames: Int = 6) -> Chord? {
            let tracker = AudioChordTracker()
            let audio = mix(midiNotes.map { tone(midi: $0, sampleRate: sampleRate, count: frameSize) })
            let chroma = extractor.chroma(frame: audio)
            for _ in 0..<frames { tracker.observe(chroma) }
            return tracker.chord
        }

        t.test("triads and sevenths are recognised from audio") {
            t.equal(detect([60, 64, 67])?.symbol(), "C", "C major")
            t.equal(detect([57, 60, 64])?.symbol(), "Am", "A minor")
            t.equal(detect([60, 64, 67, 71])?.symbol(), "Cmaj7", "C major seventh")
            t.equal(detect([55, 59, 62, 65])?.symbol(), "G7", "G dominant seventh")
            t.equal(detect([62, 65, 69, 72])?.symbol(), "Dm7", "D minor seventh")
        }

        t.test("silence reports nothing rather than guessing") {
            let tracker = AudioChordTracker()
            for _ in 0..<8 { tracker.observe(.silent) }
            t.check(tracker.chord == nil, "no chord from silence")
        }

        t.test("hysteresis stops the readout strobing") {
            let tracker = AudioChordTracker()
            let cMajor = extractor.chroma(frame: mix([60, 64, 67].map {
                tone(midi: $0, sampleRate: sampleRate, count: frameSize)
            }))
            let aMinor = extractor.chroma(frame: mix([57, 60, 64].map {
                tone(midi: $0, sampleRate: sampleRate, count: frameSize)
            }))
            for _ in 0..<8 { tracker.observe(cMajor) }
            t.equal(tracker.chord?.symbol(), "C", "settled on C")

            // One stray frame of a neighbouring chord must not move it.
            tracker.observe(aMinor)
            t.equal(tracker.chord?.symbol(), "C", "a single frame does not switch")

            for _ in 0..<10 { tracker.observe(aMinor) }
            t.equal(tracker.chord?.symbol(), "Am", "a sustained change does")
        }
    }
}
