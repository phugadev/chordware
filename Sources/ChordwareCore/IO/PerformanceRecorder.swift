import Foundation

/// Keeps what you played, so it can be handed to a DAW later.
///
/// Always recording rather than waiting to be armed. The scenario this exists
/// for is finding something good without meaning to — sitting at the keyboard
/// with no DAW open — and a record button you have to press first is exactly
/// the thing you will not have pressed.
public final class PerformanceRecorder {
    public struct Configuration: Sendable {
        public var tempo: Double
        public var ticksPerQuarter: Int
        /// Oldest notes are dropped past this, so a session left running all
        /// day cannot grow without bound.
        public var maximumNotes: Int

        public init(tempo: Double = 120,
                    ticksPerQuarter: Int = StandardMIDIFile.defaultTicksPerQuarter,
                    maximumNotes: Int = 20_000) {
            self.tempo = tempo
            self.ticksPerQuarter = ticksPerQuarter
            self.maximumNotes = maximumNotes
        }
    }

    public var configuration: Configuration
    public private(set) var notes: [StandardMIDIFile.Note] = []

    /// Notes struck but not yet released, keyed by note and channel.
    private var sounding: [Int: (start: Double, velocity: Int)] = [:]
    /// When the first note of this take arrived; everything is relative to it.
    private var origin: Double?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public var isEmpty: Bool { notes.isEmpty && sounding.isEmpty }
    public var count: Int { notes.count }

    /// Length of what has been captured, in seconds.
    public var duration: Double {
        guard let last = notes.map(\.endTick).max() else { return 0 }
        return seconds(fromTicks: last)
    }

    public func clear() {
        notes.removeAll()
        sounding.removeAll()
        origin = nil
    }

    public func noteOn(_ note: Int, velocity: Int, channel: Int = 0, at time: Double) {
        if origin == nil { origin = time }
        // A second note-on without a release closes the first, or the note
        // would never end.
        if sounding[key(note, channel)] != nil { noteOff(note, channel: channel, at: time) }
        sounding[key(note, channel)] = (time, velocity)
    }

    public func noteOff(_ note: Int, channel: Int = 0, at time: Double) {
        guard let start = sounding.removeValue(forKey: key(note, channel)), let origin else { return }
        let startTick = ticks(fromSeconds: start.start - origin)
        let endTick = ticks(fromSeconds: time - origin)
        notes.append(StandardMIDIFile.Note(
            note: note,
            velocity: start.velocity,
            startTick: startTick,
            // A note has to last something, or a DAW may drop it entirely.
            durationTicks: max(1, endTick - startTick),
            channel: channel
        ))
        if notes.count > configuration.maximumNotes {
            notes.removeFirst(notes.count - configuration.maximumNotes)
        }
    }

    /// Close anything still held, so an export mid-chord is complete.
    public func closeOpenNotes(at time: Double) {
        for stored in sounding.keys {
            noteOff(stored & 0xFF, channel: stored >> 8, at: time)
        }
    }

    public func makeFile(name: String? = "Chordware") -> Data {
        StandardMIDIFile.data(notes: notes,
                              ticksPerQuarter: configuration.ticksPerQuarter,
                              tempo: configuration.tempo,
                              name: name)
    }

    private func key(_ note: Int, _ channel: Int) -> Int { (channel << 8) | (note & 0xFF) }

    private func ticks(fromSeconds seconds: Double) -> Int {
        Int((max(0, seconds) * configuration.tempo / 60.0 * Double(configuration.ticksPerQuarter)).rounded())
    }

    private func seconds(fromTicks ticks: Int) -> Double {
        Double(ticks) / Double(configuration.ticksPerQuarter) * 60.0 / configuration.tempo
    }
}
