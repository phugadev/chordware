import ChordwareCore
import Foundation

enum Analyze {
    static func run(_ args: [String]) {
        var args = args
        let explicitKey = CLI.extractKey(&args)
        guard !args.isEmpty else { CLI.fail("nothing to analyze") }

        // One argument list can be either note names with octaves or chord
        // symbols. Notes are the more specific shape, so try those first.
        let joined = args.joined(separator: " ")
        if let notes = MIDINote.parseList(joined), notes.count >= 2 {
            voicing(notes: notes, key: explicitKey)
            return
        }
        let parsed = ChordParser.parseProgressionStrict(joined)
        if !parsed.failed.isEmpty {
            CLI.fail("could not read: \(parsed.failed.joined(separator: ", "))")
        }
        guard !parsed.chords.isEmpty else { CLI.fail("nothing to analyze") }
        progression(parsed.chords, key: explicitKey)
    }

    // MARK: - A single voicing

    static func voicing(notes: [Int], key: Key?) {
        let sorted = notes.sorted()
        let candidates = ChordDetector.detect(
            midiNotes: sorted, options: ChordDetector.Options(key: key, maxCandidates: 5))

        print("")
        print("  " + Style.dim("notes  ") + names(sorted, as: candidates.first?.chord).joined(separator: " "))

        guard let best = candidates.first else {
            if let dyad = ChordDetector.describeDyad(midiNotes: sorted) {
                print("  " + Style.dim("interval  ") + Style.bold(dyad))
            } else {
                print("  " + Style.dim("not a chord"))
            }
            print("")
            return
        }

        print("")
        print("  " + Style.heading(best.chord.symbol()) + "   " + Style.dim(best.chord.fullName))
        print("")

        // Tones with their intervals and scale degrees.
        print("  " + Style.bold("TONES"))
        for (interval, note) in best.chord.spelledTones {
            let sounding = sorted.contains { PitchClass($0) == note.pitchClass }
            let mark = sounding ? Style.green("\u{2022}") : Style.dim("\u{25E6}")
            let label = sounding ? note.name() : Style.dim(note.name())
            print("    \(mark) " + Style.pad(label, 6)
                  + Style.dim(Style.pad(interval.shortName, 6))
                  + Style.dim(interval.longName))
        }

        if candidates.count > 1 {
            print("")
            print("  " + Style.bold("ALSO READS AS"))
            for candidate in candidates.dropFirst() {
                print("    " + Style.pad(Style.cyan(candidate.chord.symbol()), 14)
                      + Style.meter(candidate.confidence)
                      + String(format: "  %.0f%%", candidate.confidence * 100))
            }
        }

        let scales = ChordScaleMap.scales(for: best.chord, limit: 5)
        if !scales.isEmpty {
            print("")
            print("  " + Style.bold("SCALES THAT FIT"))
            for fit in scales {
                let names = fit.scale.spelled(root: fit.root).map { $0.name() }.joined(separator: " ")
                print("    " + Style.pad(Style.magenta(fit.root.name() + " " + fit.scale.name), 34)
                      + Style.dim(names))
            }
        }

        if let key {
            let numeral = RomanNumeralAnalyzer.analyze(best.chord, in: key)
            print("")
            print("  " + Style.bold("IN " + key.name.uppercased()) + "   "
                  + Style.yellow(numeral.symbol) + "  "
                  + Style.dim(numeral.function.name)
                  + (numeral.explanation.map { Style.dim(" \u{2014} " + $0) } ?? ""))
        }
        print("")
    }

    /// Render played notes with the spelling the detected chord gives them, so
    /// the echoed input and the tone list cannot disagree about Bb versus A#.
    static func names(_ notes: [Int], as chord: Chord?) -> [String] {
        guard let chord else { return notes.map { MIDINote.name($0) } }
        var spellings: [Int: SpelledNote] = [:]
        for (_, note) in chord.spelledTones { spellings[note.pitchClass.value] = note }
        if let bass = chord.bass { spellings[bass.pitchClass.value] = bass }
        return notes.map { note in
            let pc = PitchClass(note)
            let spelled = spellings[pc.value]
                ?? SpelledNote.natural(pc, preferFlats: chord.root.alteration < 0)
            return spelled.name() + "\(MIDINote.octave(note))"
        }
    }

    // MARK: - A progression

    static func progression(_ chords: [Chord], key explicitKey: Key?) {
        let estimate = KeyEstimator.estimate(chords: chords)
        let key = explicitKey ?? estimate?.key
        print("")
        if let key {
            var line = "  " + Style.dim("key  ") + Style.heading(key.name)
            if explicitKey == nil, let estimate {
                line += "  " + Style.meter(estimate.confidence, width: 8)
                if let runnerUp = estimate.runnerUp {
                    line += Style.dim("  or \(runnerUp.name)")
                }
            }
            print(line)
        }
        print("")

        guard let key else {
            for chord in chords { print("  " + Style.bold(chord.symbol())) }
            print("")
            return
        }

        let numerals = RomanNumeralAnalyzer.analyze(chords, in: key)
        let width = max(12, (chords.map { $0.symbol().count }.max() ?? 8) + 4)

        var chordRow = "  "
        var numeralRow = "  "
        for (chord, numeral) in zip(chords, numerals) {
            chordRow += Style.pad(Style.bold(chord.symbol()), width)
            let coloured = numeral.isDiatonic ? Style.cyan(numeral.symbol) : Style.yellow(numeral.symbol)
            numeralRow += Style.pad(coloured, width)
        }
        print(chordRow)
        print(numeralRow)

        let annotated = numerals.enumerated().filter { $0.element.explanation != nil }
        if !annotated.isEmpty {
            print("")
            for (_, numeral) in annotated {
                print("  " + Style.pad(Style.yellow(numeral.symbol), 12)
                      + Style.dim(numeral.explanation ?? ""))
            }
        }

        var progression = Progression()
        for (index, chord) in chords.enumerated() { progression.append(chord, atMs: index * 1000) }
        let cadences = progression.cadences(in: key)
        if !cadences.isEmpty {
            print("")
            print("  " + Style.bold("CADENCES"))
            for (index, cadence) in cadences {
                let from = chords[index - 1].symbol(), to = chords[index].symbol()
                print("    " + Style.pad("\(from) \u{2192} \(to)", 20)
                      + Style.green(cadence.display))
            }
        }
        print("")
    }
}
