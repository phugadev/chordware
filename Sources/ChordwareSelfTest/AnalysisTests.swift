import ChordwareCore

private func chord(_ text: String) -> Chord {
    guard let c = ChordParser.parse(text) else { fatalError("bad chord in fixture: \(text)") }
    return c
}

private func chords(_ texts: [String]) -> [Chord] { texts.map(chord) }

func runAnalysisTests(_ t: Harness) {
    t.suite("Key estimation") {
        t.test("a ii-V-I lands in the right key") {
            let est = KeyEstimator.estimate(chords: chords(["Dm7", "G7", "Cmaj7"]))
            t.equal(est?.key.name, "C major", "ii-V-I in C")

            let minor = KeyEstimator.estimate(chords: chords(["Bm7b5", "E7", "Am7"]))
            t.equal(minor?.key.name, "A minor", "ii-V-i in A minor")

            let flat = KeyEstimator.estimate(chords: chords(["Fm7", "Bb7", "Ebmaj7"]))
            t.equal(flat?.key.name, "Eb major", "ii-V-I in Eb")
        }

        t.test("the estimate decays so modulation is followed") {
            let est = KeyEstimator(halfLife: 1.0, minimumObservations: 3.0)
            // Establish C major, then play only F# major material.
            for (i, c) in chords(["Cmaj7", "Fmaj7", "G7", "Cmaj7"]).enumerated() {
                est.observe(chord: c, at: Double(i) * 0.1)
            }
            t.equal(est.estimate?.key.mode, .major, "settles on a major key")

            // Ten half-lives later, the old material is worth ~0.1% of the new.
            for (i, c) in chords(["F#maj7", "B7", "F#maj7", "C#7", "F#maj7"]).enumerated() {
                est.observe(chord: c, at: 10.0 + Double(i) * 0.1)
            }
            t.equal(est.estimate?.key.tonic.pitchClass, PitchClass(6), "follows to F#")
        }

        t.test("borrowed chords do not drag the key into the parallel mode") {
            // The rock cadence: C major with a borrowed bVI and bVII. Two of the
            // four chords are flat-side, so pitch-class profiles alone call this
            // C minor -- but the Cmaj7 on the tonic has a natural third.
            let est = KeyEstimator.estimate(chords: chords(["Cmaj7", "Ab", "Bb7", "Cmaj7"]))
            t.equal(est?.key.name, "C major", "bVI-bVII-I stays in major")

            // And the reverse still works: a genuine minor tonic reads minor.
            let minor = KeyEstimator.estimate(chords: chords(["Cm7", "Ab", "Bb7", "Cm7"]))
            t.equal(minor?.key.name, "C minor", "the same shape with a minor tonic")
        }

        t.test("confidence separates clear keys from ambiguous material") {
            // Tested as an ordering rather than against fixed thresholds: what
            // matters is that a clear progression outranks a bare scale, which
            // outranks chromatic noise. (A bare diatonic set does legitimately
            // lean major over its relative minor — a minor key normally
            // announces itself with a raised seventh, and there is none here.)
            let clear = KeyEstimator.estimate(chords: chords(["Cmaj7", "Am7", "Dm7", "G7"]))
            let bare = KeyEstimator.estimate(pitchClasses: [0, 2, 4, 5, 7, 9, 11].map(PitchClass.init))
            let mush = KeyEstimator.estimate(pitchClasses: [0, 1, 2, 3, 4, 5, 6].map(PitchClass.init))

            t.check((clear?.confidence ?? 0) > 0.85, "a full turnaround is confident")
            t.check((bare?.confidence ?? 1) < (clear?.confidence ?? 0),
                    "a bare scale is less certain than a progression")
            t.check((mush?.confidence ?? 1) < 0.35, "chromatic material is not a key")
        }
    }

    t.suite("Roman numerals") {
        let c = Key(tonic: SpelledNote("C")!, mode: .major)

        t.test("diatonic sevenths of a major key") {
            let numerals = RomanNumeralAnalyzer.analyze(
                chords(["Cmaj7", "Dm7", "Em7", "Fmaj7", "G7", "Am7", "Bm7b5"]), in: c)
            t.equal(numerals.map(\.symbol),
                    ["Imaj7", "ii7", "iii7", "IVmaj7", "V7", "vi7", "vii\u{00F8}7"],
                    "C major diatonic")
            t.check(numerals.allSatisfy(\.isDiatonic), "all diatonic")
            t.equal(numerals.map(\.function), [.tonic, .subdominant, .tonic, .subdominant,
                                               .dominant, .tonic, .dominant], "functions")
        }

        t.test("minor keys treat the raised seventh as ordinary") {
            let am = Key(tonic: SpelledNote("A")!, mode: .minor)
            // E7 and G#dim7 use the leading tone; labelling them #V7 / #vii would
            // be wrong, they are simply V7 and vii°7 in a minor key.
            t.equal(RomanNumeralAnalyzer.analyze(chord("E7"), in: am).symbol, "V7", "V7 in minor")
            t.equal(RomanNumeralAnalyzer.analyze(chord("G#dim7"), in: am).symbol,
                    "vii\u{00B0}7", "vii°7 in minor")
            t.equal(RomanNumeralAnalyzer.analyze(chord("Am7"), in: am).symbol, "i7", "i7")
            t.equal(RomanNumeralAnalyzer.analyze(chord("Dm7"), in: am).symbol, "iv7", "iv7")
        }

        t.test("secondary dominants name their target") {
            let d7 = RomanNumeralAnalyzer.analyze(chord("D7"), in: c)
            t.equal(d7.symbol, "V7/V", "D7 tonicises V")
            t.equal(d7.function, .dominant, "still a dominant function")
            t.check(!d7.isDiatonic, "chromatic")

            t.equal(RomanNumeralAnalyzer.analyze(chord("E7"), in: c).symbol, "V7/vi", "E7 in C")
            t.equal(RomanNumeralAnalyzer.analyze(chord("A7"), in: c).symbol, "V7/ii", "A7 in C")
        }

        t.test("chromatic staples are named the way charts name them") {
            // Db7 resolving to C is the tritone substitute for G7.
            t.equal(RomanNumeralAnalyzer.analyze(chord("Db7"), in: c).symbol, "subV7/I",
                    "tritone substitute")

            // Bb7 -> Cmaj7 is the backdoor dominant. It is *also* the tritone sub
            // of V7/vi, and getting this the wrong way round is the classic
            // failure of naive analysers.
            let backdoor = RomanNumeralAnalyzer.analyze(chord("Bb7"), in: c, resolvingTo: chord("Cmaj7"))
            t.equal(backdoor.symbol, "bVII7", "backdoor dominant")
            t.equal(backdoor.explanation, "backdoor dominant", "explained")

            let cm = Key(tonic: SpelledNote("C")!, mode: .minor)
            let neapolitan = RomanNumeralAnalyzer.analyze(chord("Db"), in: cm)
            t.equal(neapolitan.symbol, "bII", "Neapolitan numeral")
            t.equal(neapolitan.explanation, "Neapolitan", "Neapolitan named")

            let borrowed = RomanNumeralAnalyzer.analyze(chord("Ab"), in: c)
            t.equal(borrowed.symbol, "bVI", "bVI in major")
            t.equal(borrowed.explanation, "borrowed from the parallel minor", "modal interchange")
        }
    }

    t.suite("Progression") {
        t.test("holding a chord extends it instead of repeating it") {
            var p = Progression()
            p.append(chord("Cmaj7"), atMs: 0)
            p.append(chord("Cmaj7"), atMs: 500)
            p.append(chord("Am7"), atMs: 1000)
            p.close(atMs: 1500)
            t.equal(p.count, 2, "two distinct chords")
            t.equal(p.events[0].durationMs, 1000, "first chord spans until the change")
            t.equal(p.events[1].durationMs, 500, "second chord closed out")
        }

        t.test("cadences are detected") {
            let c = Key(tonic: SpelledNote("C")!, mode: .major)
            var authentic = Progression()
            for (i, ch) in chords(["Dm7", "G7", "Cmaj7"]).enumerated() {
                authentic.append(ch, atMs: i * 1000)
            }
            t.equal(authentic.cadences(in: c).map(\.cadence), [.authentic], "ii-V-I is authentic")

            var deceptive = Progression()
            for (i, ch) in chords(["G7", "Am7"]).enumerated() { deceptive.append(ch, atMs: i * 1000) }
            t.equal(deceptive.cadences(in: c).map(\.cadence), [.deceptive], "V-vi is deceptive")

            var plagal = Progression()
            for (i, ch) in chords(["F", "C"]).enumerated() { plagal.append(ch, atMs: i * 1000) }
            t.equal(plagal.cadences(in: c).map(\.cadence), [.plagal], "IV-I is plagal")
        }

        t.test("a captured progression estimates its own key and renders a chart") {
            var p = Progression()
            for (i, ch) in chords(["Cmaj7", "Am7", "Dm7", "G7"]).enumerated() {
                p.append(ch, atMs: i * 2000)
            }
            t.equal(p.estimatedKey?.key.name, "C major", "estimates C major")
            let chart = p.chartText(in: p.estimatedKey?.key)
            t.check(chart.contains("Cmaj7"), "chart shows chords")
            t.check(chart.contains("vi7"), "chart shows numerals")
            t.check(chart.contains("Key: C major"), "chart shows the key")
        }
    }
}
