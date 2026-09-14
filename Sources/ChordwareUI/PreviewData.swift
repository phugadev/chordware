import ChordwareCore
import Foundation

/// A populated model for rendering, screenshots and layout checks.
///
/// Kept in the library rather than the app so the window can be exercised
/// without launching anything, which is how its layout is verified: rendering
/// offscreen needs no screen-recording permission and gives the same result
/// every run.
public enum PreviewData {
    public static func model() -> AppModel {
        let model = AppModel()
        // Rendering is synchronous and cannot wait for the readout's debounce,
        // so fixtures take it out rather than come back blank.
        model.readingDelay = 0
        let key = Key(tonic: SpelledNote("C")!, mode: .major)
        model.key = key
        model.inputLabel = "MIDI"

        // A ii-V-I with a secondary dominant and a borrowed chord, so the
        // progression strip shows both diatonic and chromatic colouring.
        let script = ["Cmaj7", "A7", "Dm7", "G7", "Ab", "Bb7"]
        for (index, symbol) in script.enumerated() {
            if let chord = ChordParser.parse(symbol) {
                // With notes, like the live path records them. Without, the
                // history strip renders chords that light no keys.
                let voicing = chord.spelledTones.map {
                    48 + $0.note.pitchClass.value + ($0.interval.semitones >= 12 ? 12 : 0)
                }
                model.progression.append(chord, atMs: index * 2000, notes: voicing.sorted())
            }
        }

        let notes = MIDINote.parseList("C3 E4 G4 Bb4 D5 A5") ?? []
        // Through the real path, so a fixture cannot show something the app
        // never could -- which is how the readout's debounce got past the
        // renders the first time.
        model.present(candidates: ChordDetector.detect(
            midiNotes: notes,
            options: ChordDetector.Options(key: key, maxCandidates: 5)),
            heldNotes: notes, atMs: 0, settled: false)
        return model
    }
}
