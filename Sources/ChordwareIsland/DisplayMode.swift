import Foundation

/// The two ways Chordware can show itself.
///
/// They differ only in what surrounds the keyboard and how big the window is,
/// never in how the instrument is drawn — one keyboard component serves both,
/// so they cannot drift apart the way an earlier duplicate did.
///
/// A third translucent, floating "overlay" mode existed briefly and was
/// removed: it was presentation mode with a different window, which is not a
/// mode, it is a preference nobody asked for.
public enum DisplayMode: String, Sendable, CaseIterable, Codable {
    /// Everything: keyboard, notes, alternatives, scales, progression.
    case companion
    /// Keyboard and one line of text, in a window shrunk to fit.
    case presentation

    public var displayName: String {
        switch self {
        case .companion: return "Companion"
        case .presentation: return "Presentation"
        }
    }

    public var usesCompactLayout: Bool { self == .presentation }
}
