import ChordwareCore
import SwiftUI

/// Placeholder rows until the generation engine lands. Kept visually identical
/// to the finished rows so the layout is already proven.
struct EmptyTabState: View {
    let message: String
    var body: some View {
        Text(message)
            .font(IslandTheme.labelFont(10))
            .foregroundStyle(IslandTheme.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SuggestTab: View {
    var model: IslandModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if model.suggestions.isEmpty {
                EmptyTabState(message: "play a chord to see what comes next")
            } else {
                ForEach(Array(model.suggestions.prefix(6).enumerated()), id: \.offset) { index, s in
                    SuggestionRow(index: index + 1, chord: s.chord, reason: s.reason)
                }
            }
        }
    }
}

struct SuggestionRow: View {
    let index: Int
    let chord: Chord
    let reason: String

    var body: some View {
        HStack(spacing: 8) {
            Text("\u{2318}\(index)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(IslandTheme.tertiary)
                .frame(width: 22, alignment: .leading)
            Text(chord.symbol(unicode: true))
                .font(IslandTheme.chordFont(12))
                .foregroundStyle(IslandTheme.primary)
                .frame(width: 74, alignment: .leading)
            Text(reason)
                .font(IslandTheme.labelFont(10))
                .foregroundStyle(IslandTheme.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

struct ReharmTab: View {
    var model: IslandModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if model.substitutions.isEmpty {
                EmptyTabState(message: "play a chord to see substitutions")
            } else {
                ForEach(Array(model.substitutions.prefix(6).enumerated()), id: \.offset) { index, s in
                    SuggestionRow(index: index + 1, chord: s.chord, reason: s.reason)
                }
            }
        }
    }
}

struct ProgressionTab: View {
    var model: IslandModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.progression.isEmpty {
                EmptyTabState(message: "nothing captured yet")
            } else {
                ProgressionStrip(model: model)
                if let key = model.key {
                    let cadences = model.progression.cadences(in: key)
                    if !cadences.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(cadences.enumerated()), id: \.offset) { _, item in
                                Text(item.cadence.display)
                                    .font(IslandTheme.labelFont(10))
                                    .foregroundStyle(IslandTheme.diatonic)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                Text("\(model.progression.count) chords captured")
                    .font(IslandTheme.labelFont(9))
                    .foregroundStyle(IslandTheme.tertiary)
            }
        }
    }
}

struct ScalesTab: View {
    var model: IslandModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            let fits = model.scaleFits
            if fits.isEmpty {
                EmptyTabState(message: "play a chord to see scales that fit")
            } else {
                ForEach(Array(fits.prefix(5).enumerated()), id: \.offset) { _, fit in
                    HStack(spacing: 8) {
                        Text("\(model.naming.name(fit.root, in: model.key)) \(fit.scale.name)")
                            .font(IslandTheme.labelFont(11))
                            .foregroundStyle(IslandTheme.primary)
                            .frame(width: 148, alignment: .leading)
                            .lineLimit(1)
                        Text(fit.scale.spelled(root: fit.root, naming: model.naming, key: model.key)
                            .joined(separator: " "))
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(IslandTheme.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}
