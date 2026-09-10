import ChordwareCore
import Foundation

enum Describe {
    static func chord(_ args: [String]) {
        guard let symbol = args.first, let chord = ChordParser.parse(symbol) else {
            CLI.fail("not a chord symbol: \(args.first ?? "")")
        }
        var rest = Array(args.dropFirst())
        let key = CLI.extractKey(&rest)
        Analyze.voicing(notes: voice(chord), key: key)
    }

    /// Lay the chord out in a plain close voicing from C3 so it can be printed
    /// and heard the same way the detector sees it.
    private static func voice(_ chord: Chord) -> [Int] {
        var notes: [Int] = []
        let base = 48 + chord.root.pitchClass.value
        for tone in chord.quality.tones.sorted(by: { $0.interval.semitones < $1.interval.semitones }) {
            notes.append(base + tone.interval.semitones)
        }
        if let bass = chord.bass {
            notes.insert(36 + bass.pitchClass.value, at: 0)
        }
        return notes.sorted()
    }

    static func scales(_ args: [String]) {
        var args = args
        var root = SpelledNote("C")!
        if let index = args.firstIndex(where: { $0 == "--root" || $0 == "-r" }), index + 1 < args.count {
            guard let parsed = SpelledNote(args[index + 1]) else { CLI.fail("not a note: \(args[index + 1])") }
            root = parsed
            args.removeSubrange(index...(index + 1))
        }
        let query = args.joined(separator: " ")
        let results = ScaleLibrary.search(query)
        guard !results.isEmpty else { CLI.fail("no scales matching \(query)") }

        print("")
        var lastCategory: ScaleCategory?
        for scale in results {
            if scale.category != lastCategory {
                print("  " + Style.heading(scale.category.rawValue))
                lastCategory = scale.category
            }
            let notes = scale.spelled(root: root).map { $0.name() }.joined(separator: " ")
            var line = "    " + Style.pad(Style.bold(root.name() + " " + scale.name), 32) + Style.dim(notes)
            if !scale.aliases.isEmpty {
                line += Style.dim("   (" + scale.aliases.joined(separator: ", ") + ")")
            }
            print(line)
        }
        print("")
        print("  " + Style.dim("\(results.count) of \(ScaleLibrary.all.count) scales"))
        print("")
    }

    static func key(_ args: [String]) {
        let joined = args.joined(separator: " ")
        var estimate: KeyEstimate?
        if let notes = MIDINote.parseList(joined), !notes.isEmpty {
            estimate = KeyEstimator.estimate(pitchClasses: notes.map { PitchClass($0) })
        } else {
            let chords = ChordParser.parseProgression(joined)
            guard !chords.isEmpty else { CLI.fail("could not read notes or chords from: \(joined)") }
            estimate = KeyEstimator.estimate(chords: chords)
        }
        guard let estimate else { CLI.fail("not enough material to estimate a key") }
        print("")
        print("  " + Style.heading(estimate.key.name) + "  " + Style.meter(estimate.confidence)
              + String(format: "  %.0f%%", estimate.confidence * 100))
        if let runnerUp = estimate.runnerUp {
            print("  " + Style.dim("runner-up  " + runnerUp.name))
        }
        print("")
    }
}
