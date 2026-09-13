import ChordwareCore
import Foundation
import Observation

/// What the island is currently showing.
public enum IslandState: Equatable, Sendable {
    /// Nothing playing; the notch is just a notch.
    case idle
    /// Something is sounding — the chord flanks the notch.
    case glance
    /// Pointer is over the island; the detail panel is down.
    case expanded
    /// Clicked; the panel is interactive and tabbed.
    case act
    /// A momentary announcement that decays back to `glance`.
    case toast(IslandToast)
}

public struct IslandToast: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case key, cadence, capture, export }
    public let kind: Kind
    public let title: String
    public let detail: String?

    public init(kind: Kind, title: String, detail: String? = nil) {
        self.kind = kind
        self.title = title
        self.detail = detail
    }

    public var symbol: String {
        switch kind {
        case .key: return "key"
        case .cadence: return "arrow.triangle.turn.up.right.diamond"
        case .capture: return "record.circle"
        case .export: return "square.and.arrow.up"
        }
    }
}

/// A proposed chord with the reason it is being proposed. Used for both
/// "what comes next" and reharmonisation, which differ only in how they are
/// generated, not in how they are shown.
public struct ChordSuggestion: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let chord: Chord
    public let reason: String
    /// How far from the obvious choice this is, 0...1.
    public let spice: Double

    public init(id: UUID = UUID(), chord: Chord, reason: String, spice: Double = 0) {
        self.id = id
        self.chord = chord
        self.reason = reason
        self.spice = spice
    }
}

public enum IslandTab: String, CaseIterable, Sendable {
    case suggest = "Next"
    case reharm = "Reharm"
    case progression = "Progression"
    case scales = "Scales"
}

/// Everything the island renders. A single observable object so the live
/// pipeline, the fake-data driver and the eventual API all push into one place.
@Observable
public final class IslandModel {
    public var state: IslandState = .idle
    public var tab: IslandTab = .suggest

    /// The current reading, best first.
    public var candidates: [ChordCandidate] = []
    public var heldNotes: [Int] = []
    public var key: Key?
    public var keyConfidence: Double = 0
    public var progression = Progression()
    /// Set when input is audio rather than MIDI, for the chroma readout.
    public var chroma: [Double]?
    public var inputLabel: String = "no input"
    /// True while notes are actually sounding.
    ///
    /// Separate from "we have a chord" on purpose: the notch collapses when you
    /// lift your hands, but a companion display should keep the last chord on
    /// screen. Both read the same model.
    public var isSounding = false
    /// The keyboard being drawn. A fixed setting, never inferred.
    public var keyboardSize: KeyboardSize = .default
    public var keyboardLowNote: Int { keyboardSize.lowNote }
    public var keyboardOctaves: Int { keyboardSize.octaves }
    /// Pedal state. Shown because a stuck pedal is otherwise invisible and
    /// looks exactly like the display refusing to let go of a chord.
    public var sustainDown = false
    /// Velocity per held note, used to shade how hard each key was struck.
    public var velocities: [Int: Int] = [:]
    /// Which display is showing. Persisted: the window remembers its size
    /// across launches, so if the mode did not, the two would disagree and the
    /// full layout could come back in a window sized for the stripped one.
    public var displayMode: DisplayMode = IslandModel.loadDisplayMode() {
        didSet { IslandModel.store(displayMode) }
    }

    private static let displayModeKey = "ChordwareDisplayMode"
    private static func loadDisplayMode() -> DisplayMode {
        UserDefaults.standard.string(forKey: displayModeKey)
            .flatMap(DisplayMode.init(rawValue:)) ?? .companion
    }
    private static func store(_ mode: DisplayMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: displayModeKey)
    }

    public var isCompactLayout: Bool { displayMode.usesCompactLayout }
    /// Set when the player has named the key rather than letting it be guessed.
    public var lockedKey: Key?
    /// How note and chord names are written.
    public var naming: NoteNaming = IslandModel.loadNaming() { didSet { IslandModel.store(naming) } }
    /// Colour held keys by their role in the chord, rather than all alike.
    public var roleColors = IslandModel.loadRoleColors() { didSet { IslandModel.store(roleColors: roleColors) } }

    private static let namingKey = "ChordwareNoteNaming"
    private static let roleColorsKey = "ChordwareRoleColors"

    private static func loadNaming() -> NoteNaming {
        let stored = UserDefaults.standard.string(forKey: namingKey)
            .flatMap(NoteNaming.init(rawValue:)) ?? .letters
        // Scale degrees are no longer offered, so a preference left set to them
        // would be stuck with no way back through the menu.
        return NoteNaming.allCases.contains(stored) ? stored : .letters
    }
    private static func store(_ naming: NoteNaming) {
        UserDefaults.standard.set(naming.rawValue, forKey: namingKey)
    }
    private static func loadRoleColors() -> Bool {
        UserDefaults.standard.object(forKey: roleColorsKey) as? Bool ?? true
    }
    private static func store(roleColors: Bool) {
        UserDefaults.standard.set(roleColors, forKey: roleColorsKey)
    }

    /// Filled by the generation engine; empty until then.
    public var suggestions: [ChordSuggestion] = []
    public var substitutions: [ChordSuggestion] = []

    public init() {}

    public var chord: Chord? { candidates.first?.chord }

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
        case 1: return "single note \u{00B7} \(MIDINote.name(heldNotes[0]))"
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

    public var confidence: Double { candidates.first?.confidence ?? 0 }
    public var alternatives: [ChordCandidate] { Array(candidates.dropFirst()) }

    public var romanNumeral: RomanNumeral? {
        guard let chord, let key else { return nil }
        return RomanNumeralAnalyzer.analyze(chord, in: key)
    }

    /// Fitting scales for the current chord, for the Scales tab.
    public var scaleFits: [(scale: Scale, root: SpelledNote, score: Double)] {
        guard let chord else { return [] }
        return ChordScaleMap.scales(for: chord, limit: 6)
    }

    /// Show notes that do not form a nameable chord, so a single key still
    /// lights up and reads out.
    public func presentNotesOnly(_ notes: [Int], atMs time: Int) {
        candidates = []
        heldNotes = notes
        isSounding = !notes.isEmpty
        switch state {
        case .idle, .glance, .toast: state = notes.isEmpty ? .idle : .glance
        case .expanded, .act: break
        }
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
        // Hovering wins: a new chord should not yank the panel shut while the
        // player is reading it.
        switch state {
        case .idle, .glance, .toast: state = .glance
        case .expanded, .act: break
        }
    }

    /// Notes released. The chord is *kept* so a companion display can go on
    /// showing what was just played; only `isSounding` and the held keys clear.
    public func clearNotes(atMs time: Int) {
        heldNotes = []
        isSounding = false
        progression.close(atMs: time)
        if case .glance = state { state = .idle }
        if case .toast = state { state = .idle }
    }

    /// Forget the chord entirely, for an explicit reset.
    public func clearChord() {
        candidates = []
        heldNotes = []
        isSounding = false
    }
}
