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

    /// Never draw more than this. A controller's octave buttons move the notes
    /// it sends, so a session that wanders up and down would otherwise teach
    /// the display a range covering everything and shrink the keys to slivers.
    private static let maxOctaves = 6
    private static let minOctaves = 2
    /// How long a note keeps counting towards the fitted range.
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
            highNote = Self.defaultHigh
            return true
        }
        lowNote = stored[0]
        highNote = stored[1]
        return true
    }

    /// Record what is being played. Returns true only when the range must widen
    /// *now* — a note outside the current view has to become visible
    /// immediately, whereas tightening can wait for a pause.
    @discardableResult
    public func observe(_ notes: [Int], now: Date = Date()) -> Bool {
        guard !notes.isEmpty else { return false }
        for note in notes { recent.append((note, now)) }
        prune(now: now)

        var changed = false
        if let lowest = notes.min(), lowest < lowNote {
            lowNote = (lowest / 12) * 12
            changed = true
        }
        if let highest = notes.max(), highest > highNote {
            highNote = ((highest + 11) / 12) * 12
            changed = true
        }
        if changed { clampAndStore() }
        return changed
    }

    /// Re-fit to recent activity. Call only when nothing is held: resizing the
    /// keyboard mid-chord moves every key under the player's eyes, which is
    /// exactly the jitter that made an earlier version unusable.
    @discardableResult
    public func settle(now: Date = Date()) -> Bool {
        prune(now: now)
        guard !recent.isEmpty else { return false }
        let notes = recent.map(\.note)
        guard let lowest = notes.min(), let highest = notes.max() else { return false }

        var targetLow = (lowest / 12) * 12
        var targetHigh = ((highest + 11) / 12) * 12
        // Pad to a usable width, centred on what is actually being played.
        while (targetHigh - targetLow) / 12 < Self.minOctaves {
            if targetLow > 0 { targetLow -= 12 }
            if (targetHigh - targetLow) / 12 < Self.minOctaves { targetHigh += 12 }
        }
        guard targetLow != lowNote || targetHigh != highNote else { return false }
        lowNote = targetLow
        highNote = targetHigh
        clampAndStore()
        return true
    }

    private func prune(now: Date) {
        recent.removeAll { now.timeIntervalSince($0.at) > Self.window }
        if recent.count > 512 { recent.removeFirst(recent.count - 512) }
    }

    private func clampAndStore() {
        lowNote = max(0, min(lowNote, 108))
        highNote = min(127, max(highNote, lowNote + 12 * Self.minOctaves))
        if (highNote - lowNote) / 12 > Self.maxOctaves {
            highNote = lowNote + 12 * Self.maxOctaves
        }
        if let deviceKey {
            defaults.set([lowNote, highNote], forKey: Self.key(for: deviceKey))
        }
    }

    /// Forget what was learned and go back to the default 49 keys.
    public func reset() {
        recent.removeAll()
        lowNote = Self.defaultLow
        highNote = Self.defaultHigh
        if let deviceKey { defaults.removeObject(forKey: Self.key(for: deviceKey)) }
    }

    private static func key(for device: String) -> String {
        "ChordwareKeyboardRange." + device
    }
}
