import Foundation

/// Terminal styling that disappears when output is piped.
enum Style {
    static let enabled = isatty(STDOUT_FILENO) == 1

    static func c(_ s: String, _ code: String) -> String {
        enabled ? "\u{1B}[\(code)m\(s)\u{1B}[0m" : s
    }

    static func bold(_ s: String) -> String { c(s, "1") }
    static func dim(_ s: String) -> String { c(s, "2") }
    static func cyan(_ s: String) -> String { c(s, "36") }
    static func green(_ s: String) -> String { c(s, "32") }
    static func yellow(_ s: String) -> String { c(s, "33") }
    static func magenta(_ s: String) -> String { c(s, "35") }
    static func heading(_ s: String) -> String { c(s, "1;36") }

    /// A confidence meter. Reading a number is slower than reading a bar.
    static func meter(_ value: Double, width: Int = 12) -> String {
        let filled = max(0, min(width, Int((value * Double(width)).rounded())))
        let bar = String(repeating: "\u{2588}", count: filled)
            + String(repeating: "\u{2591}", count: width - filled)
        let colour = value > 0.85 ? "32" : (value > 0.6 ? "33" : "2")
        return c(bar, colour)
    }

    static func pad(_ s: String, _ width: Int) -> String {
        // Pad on visible length, ignoring escape sequences.
        let visible = s.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "",
                                             options: .regularExpression).count
        return visible >= width ? s : s + String(repeating: " ", count: width - visible)
    }
}
