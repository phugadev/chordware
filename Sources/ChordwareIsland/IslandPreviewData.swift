import ChordwareCore
import Foundation

/// A populated model for rendering, screenshots and layout checks.
///
/// Kept in the library rather than the app so the window can be exercised
/// without launching anything, which is how its layout is verified: rendering
/// offscreen needs no screen-recording permission and gives the same result
/// every run.
public enum IslandPreviewData {
    public static func model() -> IslandModel {
        let model = IslandModel()
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
        model.heldNotes = notes
        model.candidates = ChordDetector.detect(
            midiNotes: notes,
            options: ChordDetector.Options(key: key, maxCandidates: 5)
        )

        model.isSounding = true
        return model
    }
}
