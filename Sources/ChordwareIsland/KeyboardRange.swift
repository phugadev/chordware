import ChordwareCore
import Foundation

/// How much of a keyboard to draw.
///
/// A 25-key controller drawn across four octaves wastes most of the display on
/// keys that will never light up, and an 88-key one runs off the end. The range
/// is learned from what actually gets played and remembered per device, so the
/// second session starts already fitted.
///
/// It only ever grows within a session. Shrinking it as you move around the
/// keyboard would resize every key under your eyes, which is the instability
/// that made the earlier adaptive version unusable.
public final class KeyboardRange {
    /// C2 to C6 - 49 keys, the most common controller size.
    public static let defaultLow = 36
    public static let defaultHigh = 84

    public private(set) var lowNote: Int
    /// Which device this range was learned from.
    public private(set) var deviceKey: String?

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lowNote = Self.defaultLow
    }

    /// How many octaves are drawn. Stable: the window slides rather than
    /// resizing, so the keys keep their proportions.
    public private(set) var octaves: Int = 4

    public var highNote: Int { lowNote + octaves * 12 }

    /// Widest and narrowest the span may become.
    private static let maxOctaves = 6
    private static let minOctaves = 2
    private static let defaultOctaves = 4
    /// How long a note keeps counting towards the fitted window.
    private static let window: TimeInterval = 30

    private var recent: [(note: Int, at: Date)] = []

    /// Switch to a device, loading anything already learned about it.
    @discardableResult
    public func use(device: String?) -> Bool {
        guard device != deviceKey else { return false }
        deviceKey = device
        recent.removeAll()
        guard let device, let stored = defaults.array(forKey: Self.key(for: device)) as? [Int],
              stored.count == 2 else {
            lowNote = Self.defaultLow
            octaves = Self.defaultOctaves
            return true
        }
        lowNote = stored[0]
        octaves = min(Self.maxOctaves, max(Self.minOctaves, stored[1]))
        return true
    }

    /// Record what is being played, sliding the window if a note falls outside
    /// it. Returns true when the view changed.
    ///
    /// Sliding rather than growing is the whole point: pressing octave-up on a
    /// controller should move which notes are shown, not how many. Growing the
    /// span reshapes every key on screen for something that is not a change of
    /// instrument.
    @discardableResult
    public func observe(_ notes: [Int], now: Date = Date()) -> Bool {
        guard let lowest = notes.min(), let highest = notes.max() else { return false }
        for note in notes { recent.append((note, now)) }
        prune(now: now)
        return frame(lowest: lowest, highest: highest)
    }

    /// Re-centre on recent playing. Call only when nothing is held: moving the
    /// keyboard mid-chord shifts every key under the player's eyes.
    @discardableResult
    public func settle(now: Date = Date()) -> Bool {
        prune(now: now)
        let notes = recent.map(\.note)
        guard let lowest = notes.min(), let highest = notes.max() else { return false }
        // Recent playing may fit in fewer octaves than the span has grown to.
        let needed = max(Self.defaultOctaves, spanNeeded(lowest: lowest, highest: highest))
        var changed = false
        if needed < octaves { octaves = needed; changed = true }
        return frame(lowest: lowest, highest: highest) || changed
    }

    private func spanNeeded(lowest: Int, highest: Int) -> Int {
        let low = (lowest / 12) * 12
        let high = ((highest + 11) / 12) * 12
        return max(Self.minOctaves, min(Self.maxOctaves, (high - low) / 12))
    }

    /// Move, and only if truly necessary widen, so both notes are visible.
    @discardableResult
    private func frame(lowest: Int, highest: Int) -> Bool {
        let previousLow = lowNote, previousOctaves = octaves
        let needed = spanNeeded(lowest: lowest, highest: highest)
        if needed > octaves { octaves = needed }

        var low = lowNote
        if lowest < low { low = (lowest / 12) * 12 }
        if highest > low + octaves * 12 {
            low = ((highest + 11) / 12) * 12 - octaves * 12
        }
        lowNote = max(0, min(low, 127 - octaves * 12))

        guard lowNote != previousLow || octaves != previousOctaves else { return false }
        store()
        return true
    }

    private func prune(now: Date) {
        recent.removeAll { now.timeIntervalSince($0.at) > Self.window }
        if recent.count > 512 { recent.removeFirst(recent.count - 512) }
    }

    private func store() {
        guard let deviceKey else { return }
        defaults.set([lowNote, octaves], forKey: Self.key(for: deviceKey))
    }

    /// Forget what was learned and go back to the default 49 keys.
    public func reset() {
        recent.removeAll()
        lowNote = Self.defaultLow
        octaves = Self.defaultOctaves
        store()
    }

    private static func key(for device: String) -> String {
        "ChordwareKeyboardRange." + device
    }
}
