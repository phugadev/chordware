import Foundation

/// The two window sizes Chordware snaps between.
///
/// This is no longer a mode: there is one layout, and it answers to the height
/// of the window it finds itself in. What is left here is the size the toggle
/// jumps to, so a repeatable window for recording is one shortcut away rather
/// than a drag. Dragging the window between the two does exactly the same
/// thing, because the layout is reading the height either way.
///
/// A third translucent, floating "overlay" mode existed briefly and was
/// removed: it was presentation mode with a different window, which is not a
/// mode, it is a preference nobody asked for.
public enum DisplayMode: String, Sendable, CaseIterable, Codable {
    /// Tall enough for the notes, the scales and the progression.
    case companion
    /// Short: the chord and the keyboard, with the chord drawn larger.
    case presentation

    public var displayName: String {
        switch self {
        case .companion: return "Companion"
        case .presentation: return "Presentation"
        }
    }

    public var usesCompactLayout: Bool { self == .presentation }
}
