import ChordwareCore
import Foundation
import Observation

/// Everything the window renders. A single observable object so the live
/// pipeline, the fake-data driver and the eventual API all push into one place.
@Observable
public final class AppModel {
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
    /// TRIAL. A chord from the history, held on screen so it can be looked at.
    ///
    /// Only ever set by clicking one. Playing anything clears it: the window's
    /// job is to say what is happening now, and an inspected chord that
    /// outlived the next thing you played would be a lie about that.
    public var inspecting: ChordEvent?

    /// What the readout is naming, which lags what is held by a breath.
    ///
    /// Fingers overlap. Playing a run, the next key goes down a few
    /// milliseconds before the last comes up, and for those milliseconds two
    /// notes really are held -- so the readout named an interval nobody
    /// played, then a chord, then a blank, several times a second. Measured on
    /// twelve seconds of real playing: eighty-eight readings, most of them on
    /// screen for under a quarter of a second and a good few under five
    /// milliseconds.
    ///
    /// The keys are not delayed. They show what is physically down, and lag
    /// there would feel like a missed note. Only the name waits, because a
    /// name is for reading and nothing readable happens in 5ms.
    private var readingNotes: [Int] = []
    private var readingCandidates: [ChordCandidate] = []
    private var readingGeneration = 0

    /// How long a reading must survive to be worth naming. Settable so tests
    /// can take the wait out rather than sleep through it.
    public var readingDelay: TimeInterval = 0.05

    public init() {}

    public var chord: Chord? { candidates.first?.chord }

    /// The chord the readout is naming.
    public var shownChord: Chord? { inspecting?.chord ?? readingCandidates.first?.chord }

    /// What the readout names. Lags `shownNotes` by `readingDelay`.
    public var readoutNotes: [Int] { inspecting?.notes ?? readingNotes }

    private func scheduleReading(candidates: [ChordCandidate], notes: [Int]) {
        readingGeneration &+= 1
        // Already on screen: only the reading of it can have changed -- a chord
        // settling, say -- and that must not wait, or a chord would be named
        // well after its own notes.
        guard notes != readingNotes else {
            readingCandidates = candidates
            return
        }
        guard readingDelay > 0 else {
            readingNotes = notes
            readingCandidates = candidates
            return
        }
        let generation = readingGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + readingDelay) { [weak self] in
            guard let self, self.readingGeneration == generation else { return }
            self.readingNotes = notes
            self.readingCandidates = candidates
        }
    }

    /// What the keyboard lights: exactly what is down, with no delay.
    public var shownNotes: [Int] {
        guard let inspecting else { return heldNotes }
        // Events carry the notes that were actually played, which is the point
        // -- you want to see what your hands did, not a textbook voicing. An
        // event recorded without them would otherwise name a chord over a blank
        // keyboard, which reads as broken rather than as missing data.
        return inspecting.notes.isEmpty ? Self.rootPosition(inspecting.chord)
                                        : inspecting.notes
    }

    /// A plain voicing from middle C up, for an event with no notes of its own.
    private static func rootPosition(_ chord: Chord) -> [Int] {
        let root = 60 + chord.root.pitchClass.value
        var notes: [Int] = []
        for tone in chord.spelledTones {
            let above = root + ((tone.note.pitchClass.value - chord.root.pitchClass.value) % 12 + 12) % 12
            notes.append(above)
        }
        return notes.sorted()
    }

    public func inspect(_ event: ChordEvent) {
        inspecting = inspecting?.id == event.id ? nil : event
    }

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
        if let chord = shownChord { return chord.symbol(naming: naming, in: key, unicode: true) }
        switch readoutNotes.count {
        case 0: return "\u{2013}\u{2009}\u{2013}\u{2009}\u{2013}"
        case 1:
            return naming.name(PitchClass(readoutNotes[0]), in: key, unicode: true)
        default:
            let names = readoutNotes.sorted().map {
                naming.name(PitchClass($0), in: key, unicode: true)
            }
            return names.joined(separator: "\u{2009}\u{2013}\u{2009}")
        }
    }

    public var displayDetail: String {
        let solfege = self.solfege
        let suffix = solfege.isEmpty ? "" : "  \u{00B7}  " + solfege
        // The chord's notes, not its spoken name. "C dominant thirteenth" is
        // the symbol above spelled out; the letters are the half that lines up
        // one-to-one with the solfège beside them, which is the whole point of
        // having both: C is Do, E is Mi, Bb is Sib.
        if let chord = shownChord {
            let letters = chord.spelledTones
                .map { naming.name($0.note, in: key, unicode: true) }.joined(separator: " ")
            return letters + suffix
        }
        switch readoutNotes.count {
        case 0: return ""
        case 1:
            // Spelled through exactly the same call as `displaySymbol`, so the
            // two lines cannot disagree. They did: Bb in the chord, A#2 in the
            // caption under it, for one key held.
            let note = readoutNotes[0]
            let name = naming.name(PitchClass(note), in: key, unicode: true)
            return "single note \u{00B7} \(name)\(MIDINote.octave(note))" + suffix
        case 2:
            let interval = ChordDetector.describeDyad(midiNotes: readoutNotes)
                .map { "interval \u{00B7} \($0)" } ?? "two notes"
            return interval + suffix
        default: return "no chord matches these notes" + suffix
        }
    }

    /// The same notes again in fixed do, so the two naming systems can be
    /// learned against each other rather than one at a time.
    ///
    /// The chord's own tones when there is a chord -- Dm7 is Re Fa La Do
    /// whichever octave you voiced it in -- and otherwise whatever is held.
    /// Fixed do, so Do is always C: the movable kind would make the same key
    /// a different syllable in every key, which is a second thing to learn
    /// rather than a way into the first.
    private var solfege: String {
        let syllables: [String]
        if let chord = shownChord {
            syllables = chord.spelledTones.map {
                NoteNaming.fixedDo.name($0.note, in: key, unicode: true)
            }
        } else {
            syllables = readoutNotes.sorted().map {
                NoteNaming.fixedDo.name(PitchClass($0), in: key, unicode: true)
            }
        }
        return syllables.joined(separator: " ")
    }
    /// Nothing has been played and nothing is held.
    ///
    /// Worth its own state rather than falling out of the others: the layout
    /// reserves room for a chord, its notes and its scales, and filling that
    /// room with labelled but empty slots -- "NOTES / nothing held", "SCALES
    /// THAT FIT / -" -- shows the scaffolding rather than the app.
    public var isEmpty: Bool { shownChord == nil && readoutNotes.isEmpty }


    /// Show notes that do not form a nameable chord, so a single key still
    /// lights up and reads out.
    public func presentNotesOnly(_ notes: [Int], atMs time: Int) {
        candidates = []
        heldNotes = notes
        isSounding = !notes.isEmpty
        if !notes.isEmpty { inspecting = nil }
        scheduleReading(candidates: [], notes: notes)
    }

    /// Push a new detection into the island, moving it out of idle.
    public func present(candidates: [ChordCandidate], heldNotes: [Int], atMs time: Int,
                        settled: Bool = true) {
        self.candidates = candidates
        self.heldNotes = heldNotes
        isSounding = !heldNotes.isEmpty
        if !heldNotes.isEmpty { inspecting = nil }
        scheduleReading(candidates: candidates, notes: heldNotes)
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
        // Through the same wait as everything else: the gaps between notes in a
        // run are a few milliseconds, and blanking the readout in them is the
        // same flicker seen from the other side.
        scheduleReading(candidates: [], notes: [])
        progression.close(atMs: time)
    }

    /// Empty the strip along the foot of the window.
    ///
    /// Its own command rather than part of panic: panic is for notes stuck
    /// down with nothing sounding, which is a fault, and clearing what you
    /// played an hour ago is not.
    public func clearHistory() {
        inspecting = nil
        progression.clear()
    }

    /// Forget the chord entirely, for an explicit reset.
    public func clearChord() {
        inspecting = nil
        candidates = []
        heldNotes = []
        isSounding = false
        // Panic and a lost device are deliberate; they do not wait.
        readingGeneration &+= 1
        readingNotes = []
        readingCandidates = []
    }
}
