import ChordwareCore

func runPitchTests(_ t: Harness) {
    t.suite("Pitch and spelling") {
        t.test("pitch class arithmetic wraps") {
            t.equal(PitchClass(-1).value, 11, "PitchClass(-1)")
            t.equal(PitchClass(12).value, 0, "PitchClass(12)")
            t.equal((PitchClass(10) + 5).value, 3, "Bb + 5 semitones")
            t.equal(PitchClass(0).distance(to: PitchClass(7)), 7, "C up to G")
            t.equal(PitchClass(7).distance(to: PitchClass(0)), 5, "G up to C")
        }

        t.test("spelling follows the degree, not the keyboard") {
            // The seventh of Ab7 is Gb, never F#. This is the whole reason
            // SpelledNote exists.
            let ab = SpelledNote(.a, -1)
            t.equal(ab.spelled(degree: 7, semitones: 10).name(), "Gb", "seventh of Ab7")
            t.equal(ab.spelled(degree: 3, semitones: 4).name(), "C", "third of Ab")
            t.equal(ab.spelled(degree: 5, semitones: 7).name(), "Eb", "fifth of Ab")

            // A diminished seventh needs a double flat to stay a seventh.
            t.equal(SpelledNote(.d, 0).spelled(degree: 7, semitones: 9).name(), "Cb",
                    "diminished seventh of D")
            // C#dim7 spells its seventh Bb: nine semitones above C# is A#/Bb,
            // and as a *seventh* the letter must be B, so B natural minus one.
            t.equal(SpelledNote(.c, 1).spelled(degree: 7, semitones: 9).name(), "Bb",
                    "diminished seventh of C#")

            // Same key, different name, decided by the degree asked for.
            let c = SpelledNote(.c, 0)
            t.equal(c.spelled(degree: 5, semitones: 8).name(), "G#", "augmented fifth of C")
            t.equal(c.spelled(degree: 6, semitones: 8).name(), "Ab", "minor sixth of C")
        }

        t.test("note names round-trip through parsing") {
            for name in ["C", "F#", "Bb", "Ebb", "A#", "G"] {
                t.equal(SpelledNote(name)?.name(), name, "round-trip \(name)")
            }
            t.check(SpelledNote("H") == nil, "H is not a note")
            t.equal(SpelledNote("F\u{266F}")?.pitchClass, PitchClass(6), "unicode sharp parses")
        }

        t.test("intervals distinguish enharmonic equivalents") {
            t.equal(Interval(degree: 4, semitones: 6).shortName, "A4", "augmented fourth")
            t.equal(Interval(degree: 5, semitones: 6).shortName, "d5", "diminished fifth")
            t.equal(Interval.perfectFifth.shortName, "P5", "perfect fifth")
            t.equal(Interval.minorSeventh.shortName, "m7", "minor seventh")
            t.equal(Interval(degree: 9, semitones: 13).shortName, "m9", "minor ninth")
            t.equal(Interval.majorThird.longName, "major third", "major third spoken")
        }

        t.test("MIDI frequency conversion") {
            t.close(MIDINote.frequency(69), 440.0, "A4 is 440Hz")
            t.close(MIDINote.frequency(60), 261.6255653, "middle C", tolerance: 1e-4)
            let (note, cents) = MIDINote.nearest(frequency: 440.0)
            t.equal(note, 69, "440Hz is MIDI 69")
            t.close(cents, 0.0, "440Hz is in tune", tolerance: 1e-6)
            t.equal(MIDINote.octave(60), 4, "middle C is C4")
        }
    }
}
