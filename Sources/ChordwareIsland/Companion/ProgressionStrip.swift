import ChordwareCore
import SwiftUI

/// The last few chords, most recent on the right.
///
/// This lived in the island's expanded panel. The island is gone; the strip is
/// not, because "what did I just play" is one of the two questions the window
/// exists to answer.
struct ProgressionStrip: View {
    var model: IslandModel

    var body: some View {
        let events = model.progression.tail(8)
        HStack(spacing: 4) {
            if events.isEmpty {
                Text("nothing captured yet")
                    .font(IslandTheme.labelFont(9))
                    .foregroundStyle(IslandTheme.tertiary)
            } else {
                ForEach(events) { event in
                    VStack(spacing: 1) {
                        Text(event.chord.symbol(naming: model.naming, in: model.key, unicode: true))
                            .font(IslandTheme.labelFont(10))
                            .foregroundStyle(event.id == events.last?.id
                                             ? IslandTheme.primary : IslandTheme.secondary)
                        if model.lockedKey != nil, let key = model.key {
                            let numeral = RomanNumeralAnalyzer.analyze(event.chord, in: key)
                            Text(numeral.symbol(naming: model.naming))
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                .foregroundStyle(numeral.isDiatonic
                                                 ? IslandTheme.diatonic.opacity(0.8)
                                                 : IslandTheme.chromatic.opacity(0.8))
                        }
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.07)))
                }
            }
            Spacer(minLength: 0)
        }
    }
}
