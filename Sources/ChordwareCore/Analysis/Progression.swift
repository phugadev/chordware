import Foundation

public enum Cadence: String, Sendable, Hashable {
    case authentic = "authentic"
    case plagal = "plagal"
    case deceptive = "deceptive"
    case half = "half"
    case backdoor = "backdoor"

    public var display: String {
        switch self {
        case .authentic: return "authentic (V\u{2013}I)"
        case .plagal: return "plagal (IV\u{2013}I)"
        case .deceptive: return "deceptive (V\u{2013}vi)"
        case .half: return "half (\u{2192} V)"
        case .backdoor: return "backdoor (bVII7\u{2013}I)"
        }
    }
}

/// One chord as it happened: what it was, when, and what was actually sounding.
public struct ChordEvent: Sendable, Hashable, Identifiable {
    public let id: UUID
    public var chord: Chord
    public var startMs: Int
    /// 0 while the chord is still sounding.
    public var durationMs: Int
    public var notes: [Int]
    public var confidence: Double

    public init(id: UUID = UUID(), chord: Chord, startMs: Int, durationMs: Int = 0,
                notes: [Int] = [], confidence: Double = 1.0) {
        self.id = id
        self.chord = chord
        self.startMs = startMs
        self.durationMs = durationMs
        self.notes = notes
        self.confidence = confidence
    }

    public var endMs: Int { startMs + durationMs }
}

/// A captured sequence of chords, and the analysis that can be run over it.
public struct Progression: Sendable, Hashable {
    public var name: String
    public var events: [ChordEvent]

    public init(name: String = "Untitled", events: [ChordEvent] = []) {
        self.name = name
        self.events = events
    }

    public var chords: [Chord] { events.map(\.chord) }
    public var isEmpty: Bool { events.isEmpty }
    public var count: Int { events.count }

    /// Add a chord, closing off the previous one. Repeats of the same chord
    /// extend the current event rather than creating a new one, so holding a
    /// voicing does not fill the timeline with duplicates.
    public mutating func append(_ chord: Chord, atMs time: Int,
                                notes: [Int] = [], confidence: Double = 1.0) {
        if var last = events.last {
            if last.chord == chord {
                last.durationMs = max(last.durationMs, time - last.startMs)
                events[events.count - 1] = last
                return
            }
            // Always close the outgoing chord against the change, not only when
            // it has never been extended — a held chord already carries a
            // duration from its own repeats and still needs closing out here.
            last.durationMs = max(last.durationMs, time - last.startMs)
            events[events.count - 1] = last
        }
        events.append(ChordEvent(chord: chord, startMs: time, notes: notes, confidence: confidence))
    }

    /// Close the final event, for when playing stops.
    public mutating func close(atMs time: Int) {
        guard var last = events.last, last.durationMs == 0 else { return }
        last.durationMs = max(0, time - last.startMs)
        events[events.count - 1] = last
    }

    public mutating func clear() { events.removeAll() }

    /// The most recent `n` chords, for the island's progression strip.
    public func tail(_ n: Int) -> [ChordEvent] { Array(events.suffix(n)) }

    public var estimatedKey: KeyEstimate? { KeyEstimator.estimate(chords: chords) }

    public func romanNumerals(in key: Key) -> [RomanNumeral] {
        RomanNumeralAnalyzer.analyze(chords, in: key)
    }

    /// Cadences found between consecutive chords, as (index of the resolution, cadence).
    public func cadences(in key: Key) -> [(index: Int, cadence: Cadence)] {
        let numerals = romanNumerals(in: key)
        guard numerals.count >= 2 else { return [] }
        var found: [(Int, Cadence)] = []
        for i in 1..<numerals.count {
            let prev = numerals[i - 1], curr = numerals[i]
            let prevIsDominantChord = chords[i - 1].quality.family == .dominant

            if prev.degree == 7, prev.accidental == -1, prevIsDominantChord, curr.degree == 1 {
                found.append((i, .backdoor))
            } else if prev.function == .dominant, prev.degree == 5, curr.degree == 6 {
                found.append((i, .deceptive))
            } else if prev.function == .dominant, curr.degree == 1 {
                found.append((i, .authentic))
            } else if prev.degree == 4, curr.degree == 1 {
                found.append((i, .plagal))
            } else if curr.degree == 5, curr.function == .dominant, i == numerals.count - 1 {
                found.append((i, .half))
            }
        }
        return found.map { (index: $0.0, cadence: $0.1) }
    }

    /// A readable chord chart with the analysis underneath, four bars per line.
    public func chartText(in key: Key?, barsPerLine: Int = 4) -> String {
        guard !events.isEmpty else { return "(empty)" }
        let numerals = key.map { romanNumerals(in: $0) } ?? []
        var lines: [String] = []
        if let key { lines.append("Key: \(key.name)") ; lines.append("") }

        var index = 0
        while index < events.count {
            let slice = Array(events[index..<min(index + barsPerLine, events.count)])
            let width = 10
            var chordRow = "|"
            var numeralRow = " "
            for (offset, event) in slice.enumerated() {
                chordRow += " " + event.chord.symbol().padded(to: width - 2) + "|"
                if index + offset < numerals.count {
                    numeralRow += " " + numerals[index + offset].symbol.padded(to: width - 1)
                }
            }
            lines.append(chordRow)
            if !numerals.isEmpty { lines.append(numeralRow) }
            lines.append("")
            index += barsPerLine
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension String {
    func padded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}
