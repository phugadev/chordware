import SwiftUI

/// The island is always dark, in both system themes, because on a notched Mac
/// it has to blend into physically black hardware. The pill on a non-notched
/// screen keeps the same palette so the two read as one product.
public enum IslandTheme {
    public static let background = Color.black
    public static let primary = Color.white
    public static let secondary = Color.white.opacity(0.62)
    public static let tertiary = Color.white.opacity(0.34)
    public static let hairline = Color.white.opacity(0.12)

    public static let accent = Color(red: 0.42, green: 0.78, blue: 1.0)
    public static let diatonic = Color(red: 0.55, green: 0.85, blue: 0.72)
    public static let chromatic = Color(red: 1.0, green: 0.78, blue: 0.42)
    public static let warn = Color(red: 1.0, green: 0.52, blue: 0.48)

    public static func chordFont(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    public static func labelFont(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

    /// Colour a confidence value the way the CLI meter does.
    public static func confidenceColor(_ value: Double) -> Color {
        value > 0.85 ? diatonic : (value > 0.6 ? chromatic : tertiary)
    }

    public static let spring = Animation.spring(response: 0.38, dampingFraction: 0.78)
    public static let quickSpring = Animation.spring(response: 0.26, dampingFraction: 0.82)
}
