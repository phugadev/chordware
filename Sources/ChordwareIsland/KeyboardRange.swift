import ChordwareCore
import Foundation

/// How much of a keyboard to draw.
///
/// Fixed, and grow-only. A displayed keyboard is a map: middle C has to be in
/// the same place every time you look at it, or reading it costs more attention
/// than it saves.
///
/// An earlier version fitted the range to recent playing, sliding and
/// re-centring between phrases. It meant one high note slid the whole
/// instrument up an octave and every other note on screen moved with it. The
/// span now starts at the 49 keys most controllers have and only ever widens,
/// once, to take in something outside it -- then stays there and is remembered
/// per device.
public final class KeyboardRange {
    /// C2 to C6 -- 49 keys, the most common controller size.
    public static let defaultLow = 36
    public static let defaultHigh = 84
    /// Past this the keys are too narrow to read.
    private static let maxOctaves = 7

    public private(set) var lowNote: Int
    public private(set) var highNote: Int
    /// Which device this range was learned from.
    public private(set) var deviceKey: String?

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lowNote = Self.defaultLow
        highNote = Self.defaultHigh
    }

    public var octaves: Int { max(1, (highNote - lowNote) / 12) }

    /// Switch to a device, loading anything already learned about it.
    @discardableResult
    public func use(device: String?) -> Bool {
        guard device != deviceKey else { return false }
        deviceKey = device
        guard let device, let stored = defaults.array(forKey: Self.key(for: device)) as? [Int],
              stored.count == 2, stored[1] > stored[0] else {
            lowNote = Self.defaultLow
            highNote = Self.defaultHigh
            return true
        }
        lowNote = stored[0]
        highNote = stored[1]
        return true
    }

    /// Widen to take in a note outside the current view. Returns true when the
    /// keyboard changed, which should be rare and never during ordinary playing.
    ///
    /// Only ever grows, and only in whole octaves, so the notes already on
    /// screen keep their pitch and their order. The alternative -- sliding to
    /// follow the hands -- moves everything.
    @discardableResult
    public func observe(_ notes: [Int]) -> Bool {
        guard let lowest = notes.min(), let highest = notes.max() else { return false }
        var low = lowNote, high = highNote
        if lowest < low { low = (lowest / 12) * 12 }
        if highest > high { high = ((highest + 11) / 12) * 12 }
        // Give up widening rather than render slivers.
        if (high - low) / 12 > Self.maxOctaves {
            if highest > highNote { low = high - Self.maxOctaves * 12 }
            else { high = low + Self.maxOctaves * 12 }
        }
        guard low != lowNote || high != highNote else { return false }
        lowNote = low
        highNote = high
        if let deviceKey { defaults.set([lowNote, highNote], forKey: Self.key(for: deviceKey)) }
        return true
    }

    /// Forget what was learned and go back to the default 49 keys.
    public func reset() {
        lowNote = Self.defaultLow
        highNote = Self.defaultHigh
        if let deviceKey { defaults.removeObject(forKey: Self.key(for: deviceKey)) }
    }

    private static func key(for device: String) -> String {
        "ChordwareKeyboardRange." + device
    }
}
