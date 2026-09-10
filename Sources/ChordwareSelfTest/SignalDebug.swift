import ChordwareCore
import ChordwareSignal
import Foundation

/// Temporary diagnostic: dumps chroma, bass and template ranking.
func dumpSignalDiagnostics() {
    let sampleRate = 44100.0
    guard let extractor = ChromaExtractor(configuration: .init(sampleRate: sampleRate)) else { return }
    let n = extractor.configuration.frameSize

    func tone(_ midi: Int, harmonics: Int = 6) -> [Float] {
        let f0 = MIDINote.frequency(midi)
        var samples = [Float](repeating: 0, count: n)
        for h in 1...harmonics {
            let f = f0 * Double(h)
            guard f < sampleRate / 2 else { break }
            let step = 2.0 * Double.pi * f / sampleRate
            for i in 0..<n { samples[i] += Float(sin(step * Double(i)) / Double(h)) }
        }
        let peak = samples.map { abs($0) }.max() ?? 1
        return samples.map { $0 / peak }
    }
    func mix(_ notes: [Int]) -> [Float] {
        var out = [Float](repeating: 0, count: n)
        for note in notes { let t = tone(note); for i in 0..<n { out[i] += t[i] } }
        let peak = out.map { abs($0) }.max() ?? 1
        return out.map { $0 / peak }
    }

    let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    for (label, notes) in [("C major", [60, 64, 67]), ("A minor", [57, 60, 64]),
                           ("Dm7", [62, 65, 69, 72])] {
        let frame = extractor.chroma(frame: mix(notes))
        print("\n\(label)  bass=\(frame.bass.map { names[$0.value] } ?? "nil")")
        let top = frame.values.enumerated().sorted { $0.element > $1.element }.prefix(6)
        print("  chroma: " + top.map { "\(names[$0.offset])=\(String(format: "%.2f", $0.element))" }
            .joined(separator: " "))
        print("  voices: " + frame.notes.map { MIDINote.name($0) }.joined(separator: " "))
        let tracker = AudioChordTracker()
        for (chord, score) in tracker.rank(frame, limit: 5) {
            print("    \(chord.symbol())  \(String(format: "%.4f", score))")
        }
    }
}
