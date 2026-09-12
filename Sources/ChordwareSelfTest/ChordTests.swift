import ChordwareCore

/// Notes written the way a musician would say them.
private func m(_ text: String) -> [Int] {
    guard let notes = MIDINote.parseList(text) else {
        fatalError("bad note list in test fixture: \(text)")
    }
    return notes
}

func runChordTests(_ t: Harness) {
    t.suite("Chord detection") {
        t.test("triads") {
            let cases: [(String, String)] = [
                ("C4 E4 G4", "C"),
                ("A3 C4 E4", "Am"),
                ("B3 D4 F4", "Bdim"),
                ("C4 E4 G#4", "Caug"),
                ("C4 F4 G4", "Csus4"),
                ("C4 D4 G4", "Csus2"),
                ("C3 G3", "C5"),
            ]
            for (notes, expected) in cases {
                t.equal(ChordDetector.best(midiNotes: m(notes))?.symbol, expected, notes)
            }
        }

        t.test("seventh chords") {
            let cases: [(String, String)] = [
                ("C4 E4 G4 B4", "Cmaj7"),
                ("C4 E4 G4 Bb4", "C7"),
                ("C4 Eb4 G4 Bb4", "Cm7"),
                ("C4 Eb4 G4 B4", "CmMaj7"),
                ("C4 Eb4 Gb4 Bb4", "Cm7b5"),
                ("C4 Eb4 Gb4 A4", "Cdim7"),
                ("C4 F4 G4 Bb4", "C7sus4"),
                ("C4 E4 G#4 Bb4", "C7#5"),
            ]
            for (notes, expected) in cases {
                t.equal(ChordDetector.best(midiNotes: m(notes))?.symbol, expected, notes)
            }
        }

        t.test("extensions and alterations") {
            let cases: [(String, String)] = [
                ("C4 E4 G4 B4 D5", "Cmaj9"),
                ("C4 E4 G4 Bb4 D5", "C9"),
                ("C4 Eb4 G4 Bb4 D5", "Cm9"),
                ("C4 E4 G4 Bb4 D5 A5", "C13"),
                ("C4 E4 G4 A4", "C6"),
                ("C4 Eb4 G4 A4", "Cm6"),
                ("C4 E4 G4 D5", "Cadd9"),
                ("C4 E4 Bb4 Db5", "C7b9"),
                ("C4 E4 Bb4 D#5", "C7#9"),
                ("C4 E4 G4 Bb4 F#5", "C7#11"),
            ]
            for (notes, expected) in cases {
                t.equal(ChordDetector.best(midiNotes: m(notes))?.symbol, expected, notes)
            }
        }

        t.test("inversions carry a slash") {
            t.equal(ChordDetector.best(midiNotes: m("E3 G3 C4"))?.symbol, "C/E", "first inversion")
            t.equal(ChordDetector.best(midiNotes: m("G3 C4 E4"))?.symbol, "C/G", "second inversion")
            t.equal(ChordDetector.best(midiNotes: m("E3 G3 Bb3 C4"))?.symbol, "C7/E", "seventh, third in bass")

            let firstInv = ChordDetector.best(midiNotes: m("E3 G3 C4"))
            t.equal(firstInv?.chord.inversion, 1, "inversion index")
            t.equal(firstInv?.chord.fullName, "C major, first inversion", "spoken name")
        }

        t.test("a foreign bass note reads as a slash chord, not a bad fit") {
            // F# is not a C major chord tone, so this is C over F#, not some
            // contorted F# quality.
            let best = ChordDetector.best(midiNotes: m("F#2 C4 E4 G4"))
            t.equal(best?.symbol, "C/F#", "C over a foreign bass")
            t.equal(best?.chord.inversion, nil, "no inversion index for a foreign bass")
        }

        t.test("the Am7 / C6 ambiguity resolves on the bass, and both are offered") {
            let overA = ChordDetector.detect(midiNotes: m("A3 C4 E4 G4"))
            t.equal(overA.first?.symbol, "Am7", "A in the bass reads Am7")
            t.check(overA.contains { $0.symbol == "C6/A" }, "C6/A still offered as an alternative")

            let overC = ChordDetector.detect(midiNotes: m("C3 E4 G4 A4"))
            t.equal(overC.first?.symbol, "C6", "C in the bass reads C6")
            t.check(overC.contains { $0.symbol == "Am7/C" }, "Am7/C still offered as an alternative")
        }

        t.test("spelling stays enharmonically correct") {
            // The seventh of Ab7 must be Gb. This is the case that makes naive
            // detectors print Ab7 with an F# in the note list.
            let ab7 = ChordDetector.best(midiNotes: m("Ab3 C4 Eb4 Gb4"))
            t.equal(ab7?.symbol, "Ab7", "flat-side dominant")
            t.equal(ab7?.chord.spelledTones.map { $0.note.name() }, ["Ab", "C", "Eb", "Gb"], "Ab7 tones")

            // Sharp-side minor keeps its sharps.
            t.equal(ChordDetector.best(midiNotes: m("C#4 E4 G#4"))?.symbol, "C#m", "sharp-side minor")
            // Flat-side major picks the flat spelling without needing a key hint.
            t.equal(ChordDetector.best(midiNotes: m("Db4 F4 Ab4"))?.symbol, "Db", "flat-side major")
        }

        t.test("key context steers spelling and ranking") {
            let ebMajor = Key(tonic: SpelledNote("Eb")!, mode: .major)
            let opts = ChordDetector.Options(key: ebMajor)
            let chord = ChordDetector.best(midiNotes: m("Eb4 G4 Bb4 D5"), options: opts)
            t.equal(chord?.symbol, "Ebmaj7", "diatonic chord in Eb")

            let eMajor = Key(tonic: SpelledNote("E")!, mode: .major)
            let sharp = ChordDetector.best(midiNotes: m("A3 C#4 E4"),
                                           options: ChordDetector.Options(key: eMajor))
            t.equal(sharp?.symbol, "A", "IV of E major")
        }

        t.test("confidence is highest for an exact match") {
            let exact = ChordDetector.best(midiNotes: m("C4 E4 G4 B4"))
            t.check((exact?.confidence ?? 0) > 0.85, "full Cmaj7 is confident")
            t.check(exact?.isExact == true, "nothing missing or extra")

            // Dropping the fifth is normal and should barely dent confidence.
            let noFifth = ChordDetector.best(midiNotes: m("C4 E4 B4"))
            t.equal(noFifth?.symbol, "Cmaj7", "shell voicing still reads Cmaj7")
            t.check((noFifth?.confidence ?? 0) > 0.7, "shell voicing stays confident")
        }

        t.test("dyads are reported as intervals") {
            t.equal(ChordDetector.describeDyad(midiNotes: m("C4 G4")), "perfect 5th", "fifth")
            t.equal(ChordDetector.describeDyad(midiNotes: m("C4 Eb4")), "minor 3rd", "minor third")
            t.equal(ChordDetector.describeDyad(midiNotes: m("C4 F#4")), "tritone", "tritone")
            t.check(ChordDetector.detect(midiNotes: m("C4")).isEmpty, "a single note is not a chord")
        }

        t.test("note name parsing round-trips") {
            t.equal(MIDINote.parse("C4"), 60, "middle C")
            t.equal(MIDINote.parse("A4"), 69, "A440")
            t.equal(MIDINote.parse("F#3"), 54, "F#3")
            t.equal(MIDINote.parse("Bb2"), 46, "Bb2")
            t.equal(MIDINote.parse("C-1"), 0, "lowest MIDI note")
            t.equal(MIDINote.name(60), "C4", "render middle C")
            t.check(MIDINote.parse("Q9") == nil, "rejects nonsense")
        }
    }
}

func runScaleTests(_ t: Harness) {
    t.suite("Scales") {
        t.test("the library is comprehensive and internally consistent") {
            t.check(ScaleLibrary.all.count >= 90,
                    "at least 90 scales, got \(ScaleLibrary.all.count)")
            let ids = ScaleLibrary.all.map(\.id)
            t.equal(Set(ids).count, ids.count, "scale ids are unique")
            for scale in ScaleLibrary.all {
                t.equal(scale.intervals.first, 0, "\(scale.name) starts at its root")
                t.equal(scale.intervals, scale.intervals.sorted(), "\(scale.name) is ascending")
                t.equal(Set(scale.intervals).count, scale.intervals.count,
                        "\(scale.name) has no duplicate degrees")
                t.check(scale.intervals.allSatisfy { $0 >= 0 && $0 < 12 },
                        "\(scale.name) stays inside one octave")
            }
        }

        t.test("modes are rotations of their parent") {
            let dorian = ScaleLibrary.scale(id: "dorian")
            t.equal(dorian?.intervals, [0, 2, 3, 5, 7, 9, 10], "Dorian")
            t.equal(ScaleLibrary.scale(id: "lydian")?.intervals, [0, 2, 4, 6, 7, 9, 11], "Lydian")
            t.equal(ScaleLibrary.scale(id: "mixolydian")?.intervals, [0, 2, 4, 5, 7, 9, 10], "Mixolydian")
            t.equal(ScaleLibrary.scale(id: "locrian")?.intervals, [0, 1, 3, 5, 6, 8, 10], "Locrian")
            t.equal(ScaleLibrary.scale(id: "altered")?.intervals, [0, 1, 3, 4, 6, 8, 10], "Altered")
            t.equal(ScaleLibrary.scale(id: "phrygian-dominant")?.intervals, [0, 1, 4, 5, 7, 8, 10],
                    "Phrygian Dominant")
            t.equal(dorian?.modeDegree, 2, "Dorian is the second mode")

            // D Dorian is the white notes, which is the point of modes.
            let dNotes = dorian?.pitchClassSet(root: PitchClass(2))
            t.equal(dNotes, Set([0, 2, 4, 5, 7, 9, 11].map(PitchClass.init)), "D Dorian is C major")
        }

        t.test("seven-note scales spell one letter per degree") {
            let eb = SpelledNote("Eb")!
            let dorian = ScaleLibrary.scale(id: "dorian")!
            t.equal(dorian.spelled(root: eb).map { $0.name() },
                    ["Eb", "F", "Gb", "Ab", "Bb", "C", "Db"], "Eb Dorian")
            let fs = SpelledNote("F#")!
            t.equal(ScaleLibrary.scale(id: "ionian")!.spelled(root: fs).map { $0.name() },
                    ["F#", "G#", "A#", "B", "C#", "D#", "E#"], "F# major keeps E#")
        }

        t.test("diatonic sevenths of the major scale") {
            let c = SpelledNote("C")!
            let chords = ScaleLibrary.scale(id: "ionian")!.diatonicChords(root: c)
            t.equal(chords.compactMap { $0?.symbol() },
                    ["Cmaj7", "Dm7", "Em7", "Fmaj7", "G7", "Am7", "Bm7b5"],
                    "C major diatonic sevenths")
        }

        t.test("chord-scale mapping finds tight fits first") {
            let c7alt = Chord(root: SpelledNote("C")!, quality: ChordDictionary.quality(id: "7#9")!)
            let fits = ChordScaleMap.scales(for: c7alt)
            t.check(fits.contains { $0.scale.id == "altered" }, "altered scale fits C7#9")

            let cmaj7 = Chord(root: SpelledNote("C")!, quality: ChordDictionary.quality(id: "maj7")!)
            let majFits = ChordScaleMap.scales(for: cmaj7)
            t.check(majFits.contains { $0.scale.id == "ionian" }, "Ionian fits Cmaj7")
            t.check(majFits.contains { $0.scale.id == "lydian" }, "Lydian fits Cmaj7")
            // A five-note scale that still covers the chord should outrank the
            // chromatic scale, which covers everything and says nothing.
            t.check(majFits.first?.scale.id != "chromatic", "chromatic is not the top suggestion")
        }

        t.test("the scales offered are ones a player would use") {
            // Ranking purely by how tightly a scale covers the chord made every
            // five-note scale beat every seven-note mode, so a D minor triad
            // was answered with Hirajoshi, Kumoi and Balinese Pelog above
            // Dorian and Aeolian. Correct set theory, useless advice.
            let dm = ChordParser.parse("Dm")!
            let top = ChordScaleMap.scales(for: dm, limit: 6).map(\.scale.id)
            for exotic in ["hirajoshi", "kumoi", "pelog", "in-sen", "iwato", "scriabin"] {
                t.check(!top.contains(exotic), "\(exotic) is not a top answer for D minor")
            }
            t.check(top.contains("minor-pentatonic"), "minor pentatonic is")
            t.check(top.contains("dorian") || top.contains("aeolian"), "and so is a minor mode")

            // The textbook answers stay on top where there is one.
            let g7 = ChordParser.parse("G7")!
            t.equal(ChordScaleMap.scales(for: g7).first?.scale.id, "mixolydian",
                    "Mixolydian leads for a dominant seventh")
            let alt = ChordScaleMap.scales(for: ChordParser.parse("C7#9")!, limit: 3).map(\.scale.id)
            t.check(alt.contains("altered") || alt.contains("diminished-hw"),
                    "an altered dominant leads with the scales for it")
        }

        t.test("search finds scales by alias") {
            t.check(ScaleLibrary.search("super locrian").contains { $0.id == "altered" },
                    "Super Locrian is an alias for Altered")
            t.check(ScaleLibrary.search("byzantine").contains { $0.id == "double-harmonic" },
                    "Byzantine is an alias for Double Harmonic")
            t.check(ScaleLibrary.search("acoustic").contains { $0.id == "lydian-dominant" },
                    "Acoustic is an alias for Lydian Dominant")
        }
    }
}

func runParserTests(_ t: Harness) {
    t.suite("Chord parsing") {
        t.test("case is load-bearing in chord suffixes") {
            // Regression: a case-insensitive match made `m7` collide with `M7`,
            // which is an alias for major seventh, turning every minor chord
            // major. These four must stay distinct.
            t.equal(ChordParser.parse("Am7")?.quality.id, "m7", "Am7 is minor")
            t.equal(ChordParser.parse("AM7")?.quality.id, "maj7", "AM7 is major")
            t.equal(ChordParser.parse("Amaj7")?.quality.id, "maj7", "Amaj7 is major")
            t.equal(ChordParser.parse("Amin7")?.quality.id, "m7", "Amin7 is minor")
        }

        t.test("round-trips written symbols") {
            for symbol in ["C", "Am", "F#m7b5", "Bbmaj9", "G7sus4", "Ebdim7", "D7#9", "C#m11"] {
                t.equal(ChordParser.parse(symbol)?.symbol(), symbol, "round-trip \(symbol)")
            }
        }

        t.test("a slash is a bass note only when it is followed by one") {
            t.equal(ChordParser.parse("Cmaj7/E")?.bass?.name(), "E", "slash bass")
            t.equal(ChordParser.parse("C/G")?.bass?.name(), "G", "slash bass on a triad")
            // C6/9 is a quality that happens to contain a slash, not a bass note.
            t.equal(ChordParser.parse("C6/9")?.quality.id, "69", "six-nine is one quality")
            t.check(ChordParser.parse("C6/9")?.bass == nil, "six-nine has no bass note")
        }

        t.test("aliases players actually type") {
            t.equal(ChordParser.parse("C-7")?.quality.id, "m7", "minus for minor")
            t.equal(ChordParser.parse("C\u{0394}")?.quality.id, "maj7", "delta for major seventh")
            t.equal(ChordParser.parse("C\u{00F8}")?.quality.id, "m7b5", "slashed o for half-diminished")
            t.equal(ChordParser.parse("Caug")?.quality.id, "aug", "aug")
            t.equal(ChordParser.parse("C+")?.quality.id, "aug", "plus for augmented")
        }

        t.test("rejects what is not a chord") {
            t.check(ChordParser.parse("") == nil, "empty")
            t.check(ChordParser.parse("H7") == nil, "H is not a note")
            t.check(ChordParser.parse("Cwobble") == nil, "unknown quality")
        }

        t.test("progressions parse and report failures") {
            t.equal(ChordParser.parseProgression("Dm7 G7 Cmaj7").map { $0.symbol() },
                    ["Dm7", "G7", "Cmaj7"], "space separated")
            t.equal(ChordParser.parseProgression("| Dm7 | G7 | Cmaj7 |").count, 3, "bar separated")
            let strict = ChordParser.parseProgressionStrict("Dm7 nonsense Cmaj7")
            t.equal(strict.chords.count, 2, "keeps what parsed")
            t.equal(strict.failed, ["nonsense"], "reports what did not")
        }
    }
}
