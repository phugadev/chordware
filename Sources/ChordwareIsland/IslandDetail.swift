import ChordwareCore
import SwiftUI

/// The panel below the notch strip in the expanded state.
struct ExpandedDetail: View {
    var model: IslandModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.displayDetail)
                    .font(IslandTheme.labelFont(11))
                    .foregroundStyle(IslandTheme.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                ConfidenceBar(value: model.confidence)
            }

            MiniPiano(heldNotes: model.heldNotes, scaleNotes: scaleNotes,
                      lowNote: model.keyboardLowNote, octaves: model.keyboardOctaves,
                      showsOctaveLabels: true, chord: model.chord)
                .frame(height: 46)

            if !model.alternatives.isEmpty {
                HStack(spacing: 5) {
                    Text("also")
                        .font(IslandTheme.labelFont(9))
                        .foregroundStyle(IslandTheme.tertiary)
                    ForEach(Array(model.alternatives.prefix(3).enumerated()), id: \.offset) { _, alt in
                        ChordChip(text: alt.chord.symbol(unicode: true))
                    }
                    Spacer(minLength: 0)
                }
            }

            ProgressionStrip(model: model)

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scaleNotes: Set<PitchClass> {
        guard let key = model.key else { return [] }
        return key.pitchClasses
    }
}

/// The interactive state: tabs the player can act on without leaving their DAW.
struct ActDetail: View {
    @Bindable var model: IslandModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(IslandTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(IslandTheme.quickSpring) { model.tab = tab }
                    } label: {
                        Text(tab.rawValue)
                            .font(IslandTheme.labelFont(10))
                            .foregroundStyle(model.tab == tab ? IslandTheme.primary : IslandTheme.tertiary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background {
                                if model.tab == tab {
                                    Capsule().fill(Color.white.opacity(0.14))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 8)

            Divider().overlay(IslandTheme.hairline)

            Group {
                switch model.tab {
                case .suggest: SuggestTab(model: model)
                case .reharm: ReharmTab(model: model)
                case .progression: ProgressionTab(model: model)
                case .scales: ScalesTab(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}

struct ConfidenceBar: View {
    let value: Double
    var width: CGFloat = 54

    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.white.opacity(0.14))
                .frame(width: width, height: 3)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(IslandTheme.accent.opacity(0.55 + 0.45 * max(0, min(1, value))))
                        .frame(width: width * max(0, min(1, value)), height: 3)
                }
            Text("\(Int((value * 100).rounded()))%")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(IslandTheme.tertiary)
        }
    }
}

struct ChordChip: View {
    let text: String
    var tint: Color = IslandTheme.secondary

    var body: some View {
        Text(text)
            .font(IslandTheme.labelFont(10))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.09)))
    }
}

/// The last few chords, most recent on the right.
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
                        Text(event.chord.symbol(unicode: true))
                            .font(IslandTheme.labelFont(10))
                            .foregroundStyle(event.id == events.last?.id
                                             ? IslandTheme.primary : IslandTheme.secondary)
                        if let key = model.key {
                            let numeral = RomanNumeralAnalyzer.analyze(event.chord, in: key)
                            Text(numeral.symbol)
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
