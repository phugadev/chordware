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
@MainActor
public final class KeyboardRange {
    /// C2 to C6 - 49 keys, the most common controller size.
    public nonisolated static let defaultLow = 36
    public nonisolated static let defaultHigh = 84

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
              stored.count == 2 else {
            lowNote = Self.defaultLow
            highNote = Self.defaultHigh
            return true
        }
        lowNote = stored[0]
        highNote = stored[1]
        return true
    }

    /// Widen to include these notes. Returns true when the range changed.
    @discardableResult
    public func observe(_ notes: [Int]) -> Bool {
        guard let lowest = notes.min(), let highest = notes.max() else { return false }
        var changed = false
        // Snap outward to whole octaves so the leftmost key is always a C.
        let flooredC = (lowest / 12) * 12
        let ceilingC = ((highest + 11) / 12) * 12
        if flooredC < lowNote { lowNote = flooredC; changed = true }
        if ceilingC > highNote { highNote = ceilingC; changed = true }
        if changed, let deviceKey {
            defaults.set([lowNote, highNote], forKey: Self.key(for: deviceKey))
        }
        return changed
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
