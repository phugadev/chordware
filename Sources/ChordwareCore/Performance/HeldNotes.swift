import Foundation

/// Which notes are currently sounding, accounting for the sustain pedal.
///
/// Kept pure and separate from CoreMIDI so the pedal logic — the part that is
/// actually easy to get wrong — can be tested without hardware.
public struct HeldNotes: Sendable, Equatable {
    /// Keys physically down right now.
    private var keysDown: [Int: Int] = [:]
    /// Keys released while the pedal was down, still ringing.
    private var sustained: Set<Int> = []
    public private(set) var sustainDown = false

    public init() {}

    /// Every sounding note, low to high.
    public var sounding: [Int] {
        Set(keysDown.keys).union(sustained).sorted()
    }

    public var isEmpty: Bool { keysDown.isEmpty && sustained.isEmpty }
    public var count: Int { Set(keysDown.keys).union(sustained).count }

    /// Velocity of a sounding key, for weighting the detector later.
    public func velocity(of note: Int) -> Int? { keysDown[note] }

    /// Velocity of every key currently down.
    public var velocities: [Int: Int] { keysDown }

    public var averageVelocity: Int {
        guard !keysDown.isEmpty else { return 0 }
        return keysDown.values.reduce(0, +) / keysDown.count
    }

    @discardableResult
    public mutating func noteOn(_ note: Int, velocity: Int = 100) -> Bool {
        // A note-on with zero velocity is a note-off; plenty of hardware sends
        // running-status note-ons rather than 0x80.
        if velocity == 0 { return noteOff(note) }
        let changed = keysDown[note] == nil || sustained.contains(note)
        keysDown[note] = velocity
        // Retriggering a sustained note makes it a live key again.
        sustained.remove(note)
        return changed
    }

    @discardableResult
    public mutating func noteOff(_ note: Int) -> Bool {
        guard keysDown.removeValue(forKey: note) != nil else { return false }
        if sustainDown {
            sustained.insert(note)
            // Still sounding, so the chord has not changed.
            return false
        }
        return true
    }

    /// Returns true when the set of sounding notes changed.
    @discardableResult
    public mutating func setSustain(_ down: Bool) -> Bool {
        guard down != sustainDown else { return false }
        sustainDown = down
        guard !down else { return false }
        let had = !sustained.isEmpty
        sustained.removeAll()
        return had
    }

    @discardableResult
    public mutating func allNotesOff() -> Bool {
        let changed = !isEmpty
        keysDown.removeAll()
        sustained.removeAll()
        return changed
    }
}
