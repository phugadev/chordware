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

    /// Filled by the generation engine; empty until then.
    public var suggestions: [ChordSuggestion] = []
    public var substitutions: [ChordSuggestion] = []

    public init() {}

    public var chord: Chord? { candidates.first?.chord }
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

    /// Push a new detection into the island, moving it out of idle.
    public func present(candidates: [ChordCandidate], heldNotes: [Int], atMs time: Int) {
        self.candidates = candidates
        self.heldNotes = heldNotes
        if let chord = candidates.first?.chord {
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

    public func clearNotes(atMs time: Int) {
        heldNotes = []
        candidates = []
        progression.close(atMs: time)
        if case .glance = state { state = .idle }
        if case .toast = state { state = .idle }
    }
}
