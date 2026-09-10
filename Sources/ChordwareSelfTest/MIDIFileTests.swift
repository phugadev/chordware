import ChordwareCore
import Foundation

func runMIDIFileTests(_ t: Harness) {
    t.suite("Standard MIDI files") {
        t.test("notes survive a write and read") {
            let notes = [
                StandardMIDIFile.Note(note: 60, velocity: 100, startTick: 0, durationTicks: 480),
                StandardMIDIFile.Note(note: 64, velocity: 88, startTick: 0, durationTicks: 480),
                StandardMIDIFile.Note(note: 67, velocity: 92, startTick: 240, durationTicks: 720),
            ]
            let data = StandardMIDIFile.data(notes: notes, tempo: 96, name: "Take 1")
            guard let read = StandardMIDIFile.read(data) else {
                t.check(false, "could not read back what was written"); return
            }
            t.equal(read.notes.count, 3, "all three notes")
            t.equal(Set(read.notes.map(\.note)), Set([60, 64, 67]), "same pitches")
            t.equal(read.notes.first { $0.note == 67 }?.startTick, 240, "start preserved")
            t.equal(read.notes.first { $0.note == 67 }?.durationTicks, 720, "duration preserved")
            t.equal(read.notes.first { $0.note == 60 }?.velocity, 100, "velocity preserved")
            t.close(read.tempo, 96, "tempo preserved", tolerance: 0.5)
            t.equal(read.name, "Take 1", "track name preserved")
        }

        t.test("overlapping notes stay separate") {
            // A held chord under a melody produces notes that start and stop
            // inside each other; writing them note by note would interleave the
            // offs wrongly and merge them.
            let notes = [
                StandardMIDIFile.Note(note: 48, velocity: 90, startTick: 0, durationTicks: 1920),
                StandardMIDIFile.Note(note: 72, velocity: 80, startTick: 240, durationTicks: 240),
                StandardMIDIFile.Note(note: 74, velocity: 80, startTick: 480, durationTicks: 240),
            ]
            let read = StandardMIDIFile.read(StandardMIDIFile.data(notes: notes))
            t.equal(read?.notes.count, 3, "three distinct notes")
            t.equal(read?.notes.first { $0.note == 48 }?.durationTicks, 1920, "the long note is intact")
        }

        t.test("a repeated note is released before it is struck again") {
            let notes = [
                StandardMIDIFile.Note(note: 60, velocity: 90, startTick: 0, durationTicks: 480),
                StandardMIDIFile.Note(note: 60, velocity: 70, startTick: 480, durationTicks: 480),
            ]
            let read = StandardMIDIFile.read(StandardMIDIFile.data(notes: notes))
            t.equal(read?.notes.count, 2, "two separate strikes, not one merged note")
            t.equal(read?.notes.map(\.startTick), [0, 480], "both start times kept")
        }

        t.test("variable-length delta times round-trip past one byte") {
            // Deltas above 127 need multi-byte encoding; getting this wrong
            // corrupts every timing in a file longer than a bar or so.
            let notes = [
                StandardMIDIFile.Note(note: 60, velocity: 90, startTick: 0, durationTicks: 96),
                StandardMIDIFile.Note(note: 62, velocity: 90, startTick: 100_000, durationTicks: 96),
            ]
            let read = StandardMIDIFile.read(StandardMIDIFile.data(notes: notes))
            t.equal(read?.notes.last?.startTick, 100_000, "a far-off note keeps its position")
        }

        t.test("rubbish is rejected rather than half-parsed") {
            t.check(StandardMIDIFile.read(Data()) == nil, "empty")
            t.check(StandardMIDIFile.read(Data([0, 1, 2, 3, 4, 5, 6, 7])) == nil, "not a MIDI file")
        }
    }

    t.suite("Performance recording") {
        t.test("held notes become timed notes") {
            let recorder = PerformanceRecorder()
            recorder.noteOn(60, velocity: 100, at: 10.0)   // clock need not start at zero
            recorder.noteOn(64, velocity: 90, at: 10.0)
            recorder.noteOff(60, at: 10.5)
            recorder.noteOff(64, at: 10.5)
            t.equal(recorder.count, 2, "two notes captured")
            // At 120bpm a quarter note is 0.5s, so half a second is 480 ticks.
            t.equal(recorder.notes.first?.startTick, 0, "timed from the first note, not the clock")
            t.equal(recorder.notes.first?.durationTicks, 480, "half a second is a quarter note")
        }

        t.test("a note struck twice without release still ends") {
            // Hardware drops note-offs. Without this the note runs to the end
            // of the file and the export is unusable.
            let recorder = PerformanceRecorder()
            recorder.noteOn(60, velocity: 100, at: 0)
            recorder.noteOn(60, velocity: 100, at: 1.0)
            recorder.noteOff(60, at: 1.5)
            t.equal(recorder.count, 2, "the first strike was closed by the second")
        }

        t.test("exporting mid-chord closes what is still held") {
            let recorder = PerformanceRecorder()
            recorder.noteOn(60, velocity: 100, at: 0)
            recorder.noteOn(67, velocity: 100, at: 0)
            t.equal(recorder.count, 0, "nothing complete yet")
            recorder.closeOpenNotes(at: 1.0)
            t.equal(recorder.count, 2, "both closed")
            t.check(recorder.notes.allSatisfy { $0.durationTicks > 0 }, "and given a real length")
        }

        t.test("a whole performance round-trips to a file") {
            let recorder = PerformanceRecorder()
            let script: [(Int, Double, Double)] = [
                (60, 0.0, 0.9), (64, 0.0, 0.9), (67, 0.0, 0.9),
                (62, 1.0, 1.9), (65, 1.0, 1.9), (69, 1.0, 1.9),
            ]
            for (note, on, off) in script {
                recorder.noteOn(note, velocity: 96, at: on)
                recorder.noteOff(note, at: off)
            }
            let read = StandardMIDIFile.read(recorder.makeFile())
            t.equal(read?.notes.count, 6, "every note survived")
            t.equal(Set(read?.notes.map(\.note) ?? []), Set([60, 62, 64, 65, 67, 69]), "same pitches")
            t.check((recorder.duration - 1.9) < 0.05, "duration matches the take")
        }

        t.test("the buffer is bounded") {
            let recorder = PerformanceRecorder(configuration: .init(maximumNotes: 10))
            for i in 0..<50 {
                recorder.noteOn(60, velocity: 90, at: Double(i))
                recorder.noteOff(60, at: Double(i) + 0.5)
            }
            t.equal(recorder.count, 10, "oldest notes dropped, session left running is safe")
        }
    }
}
