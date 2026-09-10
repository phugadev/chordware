import Foundation

/// The three ways Chordware can show itself.
///
/// They differ only in what surrounds the keyboard and how the window behaves,
/// never in how the instrument is drawn — one keyboard component serves all
/// three, so they cannot drift apart the way an earlier duplicate did.
public enum DisplayMode: String, Sendable, CaseIterable, Codable {
    /// Everything: keyboard, notes, alternatives, scales, progression.
    case companion
    /// Keyboard and one line of text, in a window shrunk to fit.
    case compact
    /// Compact, translucent and floating above other apps.
    case overlay

    public var displayName: String {
        switch self {
        case .companion: return "Companion"
        case .compact: return "Compact"
        case .overlay: return "Overlay"
        }
    }

    /// Overlay and compact share a layout; only the window differs.
    public var usesCompactLayout: Bool { self != .companion }
    public var floatsAboveOtherApps: Bool { self == .overlay }
    public var isTranslucent: Bool { self == .overlay }
}
