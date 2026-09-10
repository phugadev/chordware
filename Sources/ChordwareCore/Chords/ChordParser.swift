import Foundation

/// Reads written chord symbols back into `Chord` values.
///
/// Needed by the CLI, the HTTP API and the progression editor, all of which
/// take chords as text. Accepts the aliases players actually type: `-7` and
/// `min7` for `m7`, `Δ` for `maj7`, `ø` for `m7b5`.
public enum ChordParser {
    public static func parse(_ text: String) -> Chord? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        var body = trimmed
        var bass: SpelledNote?

        // A trailing slash may be a bass note (Cmaj7/E) or part of the quality
        // itself (C6/9), so only split when what follows is actually a note.
        if let slash = trimmed.lastIndex(of: "/") {
            let after = String(trimmed[trimmed.index(after: slash)...])
            if let note = SpelledNote(after), !after.isEmpty {
                bass = note
                body = String(trimmed[trimmed.startIndex..<slash])
            }
        }

        var chars = Array(body)
        guard let first = chars.first, Letter(character: first) != nil else { return nil }
        var rootText = String(chars.removeFirst())
        // Greedily take accidentals; no chord quality begins with one.
        while let next = chars.first,
              next == "#" || next == "b" || next == "\u{266F}" || next == "\u{266D}"
                  || next == "x" || next == "\u{1D12A}" || next == "\u{1D12B}" {
            rootText.append(chars.removeFirst())
        }
        guard let root = SpelledNote(rootText) else { return nil }

        let suffix = String(chars)
        guard let quality = matchQuality(suffix) else { return nil }
        return Chord(root: root, quality: quality, bass: bass)
    }

    private static func matchQuality(_ suffix: String) -> ChordQuality? {
        if suffix.isEmpty { return ChordDictionary.quality(id: "maj") }
        // Case-sensitive on purpose. `m7` is minor and `M7` is major, so a
        // case-insensitive match here turns every minor chord into a major one.
        // symbolsByLength is sorted longest-first, so `maj7` wins over `maj`.
        for (symbol, quality) in ChordDictionary.symbolsByLength where !symbol.isEmpty {
            if symbol == suffix { return quality }
        }
        return nil
    }

    /// Parse a chord sequence written as `Dm7 G7 Cmaj7` or `| Dm7 | G7 | Cmaj7 |`.
    public static func parseProgression(_ text: String) -> [Chord] {
        text.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "|" || $0 == "\n" || $0 == "\t" })
            .compactMap { parse(String($0)) }
    }

    /// Parse a sequence, reporting which tokens failed rather than silently
    /// dropping them — the CLI and API need to tell the user what they mistyped.
    public static func parseProgressionStrict(_ text: String) -> (chords: [Chord], failed: [String]) {
        var chords: [Chord] = []
        var failed: [String] = []
        for token in text.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "|" || $0 == "\n" || $0 == "\t" }) {
            if let chord = parse(String(token)) { chords.append(chord) } else { failed.append(String(token)) }
        }
        return (chords, failed)
    }
}
