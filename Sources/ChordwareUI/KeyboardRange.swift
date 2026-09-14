import ChordwareCore
import Foundation

/// How many keys to draw.
///
/// A fixed setting, never inferred and never adjusted while you play. Two
/// earlier versions tried to be clever: one re-fitted to recent playing and
/// slid the whole instrument when you moved your hands, the other grew to take
/// in anything outside its range, so the controller's octave buttons kept
/// adding keys. Both were reported as the keyboard shifting, because both were.
///
/// A note outside the chosen range simply is not drawn. That is a visible,
/// predictable limit the player can fix by choosing a wider keyboard, which is
/// better than a display that rearranges itself.
public enum KeyboardSize: String, Sendable, CaseIterable, Codable {
    case twoOctaves, fourOctaves, fiveOctaves, sixOctaves, sevenOctaves

    /// Lowest note, always a C so the leftmost key is a landmark.
    public var lowNote: Int {
        switch self {
        case .twoOctaves: return 48    // C3
        case .fourOctaves: return 36   // C2
        case .fiveOctaves: return 36   // C2
        case .sixOctaves: return 24    // C1
        case .sevenOctaves: return 24  // C1
        }
    }

    public var octaves: Int {
        switch self {
        case .twoOctaves: return 2
        case .fourOctaves: return 4
        case .fiveOctaves: return 5
        case .sixOctaves: return 6
        case .sevenOctaves: return 7
        }
    }

    public var highNote: Int { lowNote + octaves * 12 }
    /// Total keys, black and white, which is how controllers are sold:
    /// four octaves is a 49-key, not a 29-key.
    public var keyCount: Int { octaves * 12 + 1 }

    public var displayName: String {
        let low = MIDINote.name(lowNote), high = MIDINote.name(highNote)
        return "\(low)\u{2013}\(high)  (\(keyCount) keys)"
    }

    public static let `default` = KeyboardSize.fourOctaves
}

/// The chosen keyboard, remembered across launches.
public final class KeyboardRange {
    private static let key = "ChordwareKeyboardSize"
    private let defaults: UserDefaults

    public private(set) var size: KeyboardSize

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        size = defaults.string(forKey: Self.key)
            .flatMap(KeyboardSize.init(rawValue:)) ?? .default
    }

    public var lowNote: Int { size.lowNote }
    public var octaves: Int { size.octaves }
    public var highNote: Int { size.highNote }

    /// Returns true when the drawn keyboard changed, which only ever happens
    /// because the player asked for it.
    @discardableResult
    public func set(_ newSize: KeyboardSize) -> Bool {
        guard newSize != size else { return false }
        size = newSize
        defaults.set(newSize.rawValue, forKey: Self.key)
        return true
    }

    public func reset() { set(.default) }
}
