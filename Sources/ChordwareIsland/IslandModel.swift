import ChordwareCore
import Foundation
import Observation

/// Everything the window renders. A single observable object so the live
/// pipeline, the fake-data driver and the eventual API all push into one place.
@Observable
public final class IslandModel {
    /// The current reading, best first.
    public var candidates: [ChordCandidate] = []
    public var heldNotes: [Int] = []
    /// The detected key. Nothing on screen says what it is: it is here so a
    /// chord is spelled the way the music means it -- the seventh of Ab7 is Gb,
    /// never F# -- which is the one thing key detection buys a display this
    /// small.
    public var key: Key?
    public var progression = Progression()
    public var inputLabel: String = "no input"
    /// True while notes are actually sounding.
    ///
    /// Separate from "we have a chord" on purpose: the chord stays on screen
    /// after you lift your hands -- that is most of what makes the window
    /// useful for teaching -- but the keys must go out the moment you do.
    public var isSounding = false
    /// The keyboard being drawn. A fixed setting, never inferred.
    public var keyboardSize: KeyboardSize = .default
    public var keyboardLowNote: Int { keyboardSize.lowNote }
    public var keyboardOctaves: Int { keyboardSize.octaves }
    /// Pedal state. Shown because a stuck pedal is otherwise invisible and
    /// looks exactly like the display refusing to let go of a chord.
    public var sustainDown = false
    public init() {}

    public var chord: Chord? { candidates.first?.chord }

    /// How note and chord names are written. Letters, always -- the menu that
    /// offered solfège and scale degrees was two more things to get wrong.
    public var naming: NoteNaming { .letters }

    /// What to put where the chord symbol goes.
    ///
    /// One key is not a chord and two are an interval, but both are worth
    /// showing: silence there makes the app look broken when it is working
    /// correctly, and for teaching or screen recording the single note is
    /// exactly what the viewer needs to see.
    public var displaySymbol: String {
        if let chord { return chord.symbol(naming: naming, in: key, unicode: true) }
        switch heldNotes.count {
        case 0: return "\u{2013}\u{2009}\u{2013}\u{2009}\u{2013}"
        case 1:
            return naming.name(PitchClass(heldNotes[0]), in: key, unicode: true)
        default:
            let names = heldNotes.sorted().map {
                naming.name(PitchClass($0), in: key, unicode: true)
            }
            return names.joined(separator: "\u{2009}\u{2013}\u{2009}")
        }
    }

    public var displayDetail: String {
        if let chord { return chord.spokenName(naming: naming, in: key) }
        switch heldNotes.count {
        case 0: return ""
        case 1:
            // Spelled through exactly the same call as `displaySymbol`, so the
            // two lines cannot disagree. They did: Bb in the chord, A#2 in the
            // caption under it, for one key held.
            let note = heldNotes[0]
            let name = naming.name(PitchClass(note), in: key, unicode: true)
            return "single note \u{00B7} \(name)\(MIDINote.octave(note))"
        case 2:
            return ChordDetector.describeDyad(midiNotes: heldNotes).map { "interval \u{00B7} \($0)" }
                ?? "two notes"
        default: return "no chord matches these notes"
        }
    }
    /// Nothing has been played and nothing is held.
    ///
    /// Worth its own state rather than falling out of the others: the layout
    /// reserves room for a chord, its notes and its scales, and filling that
    /// room with labelled but empty slots -- "NOTES / nothing held", "SCALES
    /// THAT FIT / -" -- shows the scaffolding rather than the app.
    public var isEmpty: Bool { chord == nil && heldNotes.isEmpty }


    /// Show notes that do not form a nameable chord, so a single key still
    /// lights up and reads out.
    public func presentNotesOnly(_ notes: [Int], atMs time: Int) {
        candidates = []
        heldNotes = notes
        isSounding = !notes.isEmpty
    }

    /// Push a new detection into the island, moving it out of idle.
    public func present(candidates: [ChordCandidate], heldNotes: [Int], atMs time: Int,
                        settled: Bool = true) {
        self.candidates = candidates
        self.heldNotes = heldNotes
        isSounding = !heldNotes.isEmpty
        // Only a settled chord goes into the history. A hand landing on G major
        // passes through B minor on its way, and a progression strip full of
        // chords nobody played is worse than no strip at all.
        if settled, let chord = candidates.first?.chord {
            progression.append(chord, atMs: time, notes: heldNotes,
                               confidence: candidates.first?.confidence ?? 1)
        }
    }

    /// Notes released: the readout empties back to its dashes.
    ///
    /// The chord used to be kept on screen after you lifted your hands, on the
    /// theory that a teaching display should go on showing what was just
    /// played. In use it is the opposite: a chord name with no keys lit under
    /// it is a display that has not noticed you stopped, and there is no way to
    /// tell it apart from one that has frozen. What was played is in the
    /// capture; the window says what *is* being played.
    public func clearNotes(atMs time: Int) {
        heldNotes = []
        isSounding = false
        candidates = []
        progression.close(atMs: time)
    }

    /// Forget the chord entirely, for an explicit reset.
    public func clearChord() {
        candidates = []
        heldNotes = []
        isSounding = false
    }
}
