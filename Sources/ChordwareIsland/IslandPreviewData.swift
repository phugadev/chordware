import ChordwareCore
import Foundation

/// A populated model for rendering, screenshots and layout checks.
///
/// Kept in the library rather than the app so the island can be exercised
/// without launching anything, which is how its layout is verified: rendering
/// offscreen needs no screen-recording permission and gives the same result
/// every run.
public enum IslandPreviewData {
    public static func model(state: IslandState = .expanded) -> IslandModel {
        let model = IslandModel()
        let key = Key(tonic: SpelledNote("C")!, mode: .major)
        model.key = key
        model.keyConfidence = 0.94
        model.inputLabel = "MIDI"

        // A ii-V-I with a secondary dominant and a borrowed chord, so the
        // progression strip shows both diatonic and chromatic colouring.
        let script = ["Cmaj7", "A7", "Dm7", "G7", "Ab", "Bb7"]
        for (index, symbol) in script.enumerated() {
            if let chord = ChordParser.parse(symbol) {
                model.progression.append(chord, atMs: index * 2000)
            }
        }

        let notes = MIDINote.parseList("C3 E4 G4 Bb4 D5 A5") ?? []
        model.heldNotes = notes
        // A spread of velocities, so the dynamics shading is visible.
        let spread = [118, 74, 96, 52, 105, 66]
        model.velocities = Dictionary(uniqueKeysWithValues: notes.enumerated().map {
            ($0.element, spread[$0.offset % spread.count])
        })
        model.candidates = ChordDetector.detect(
            midiNotes: notes,
            options: ChordDetector.Options(key: key, maxCandidates: 5)
        )

        model.suggestions = [
            suggestion("Fmaj7", "resolves down a fifth", 0.1),
            suggestion("Cmaj7", "tonic, strongest landing", 0.0),
            suggestion("Db7", "tritone sub, chromatic approach", 0.7),
            suggestion("Fm7", "borrowed iv, softens the arrival", 0.5),
            suggestion("Abmaj7", "bVI, lifts to a new colour", 0.6),
            suggestion("Bm7b5", "sets up a minor ii-V", 0.4),
        ]
        model.substitutions = [
            suggestion("Db7", "tritone substitute", 0.6),
            suggestion("C13", "extend without changing function", 0.1),
            suggestion("Gm7 C7", "split into a ii-V", 0.3),
            suggestion("Bb7", "backdoor approach", 0.5),
            suggestion("C7alt", "altered tensions", 0.8),
        ]

        model.isSounding = true
        model.state = state
        return model
    }

    private static func suggestion(_ symbol: String, _ reason: String, _ spice: Double) -> ChordSuggestion {
        ChordSuggestion(chord: ChordParser.parse(symbol.split(separator: " ").first.map(String.init) ?? symbol)
                            ?? ChordParser.parse("C")!,
                        reason: reason, spice: spice)
    }
}
