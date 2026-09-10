import ChordwareCore
import SwiftUI

/// The full-size display, meant to sit on a second screen beside the keyboard.
///
/// The notch is right for a glance while your hands are busy, but it is the
/// wrong shape for actually watching what you play: it is above the screen you
/// are looking at, and it collapses the moment you lift your hands. This window
/// is the opposite — large, persistent, and placeable wherever you can see it.
public struct CompanionView: View {
    @Bindable public var model: IslandModel
    public var onClose: (() -> Void)?

    public init(model: IslandModel, onClose: (() -> Void)? = nil) {
        self.model = model
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(IslandTheme.hairline)
            keyboard
            Divider().overlay(IslandTheme.hairline)
            detail
            legend
            Spacer(minLength: 0)
            footer
        }
        .background(IslandTheme.background)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.displaySymbol)
                    .font(.system(size: 60, weight: .semibold, design: .rounded))
                    .foregroundStyle(model.isSounding ? IslandTheme.primary : IslandTheme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .contentTransition(.numericText())
                Text(model.displayDetail)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(IslandTheme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                if let numeral = model.romanNumeral {
                    Text(numeral.symbol)
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .foregroundStyle(numeral.isDiatonic ? IslandTheme.diatonic : IslandTheme.chromatic)
                        .lineLimit(1)
                    Text(numeral.explanation ?? numeral.function.name)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(IslandTheme.tertiary)
                        .lineLimit(1)
                }
                if let key = model.key {
                    Text("key of \(key.name)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(IslandTheme.secondary)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Keyboard

    private var keyboard: some View {
        MiniPiano(heldNotes: model.heldNotes,
                  scaleNotes: model.key?.pitchClasses ?? [],
                  lowNote: model.keyboardLowNote,
                  octaves: model.keyboardOctaves,
                  showsOctaveLabels: true,
                  namesHeldNotes: true,
                  chord: model.chord)
            .frame(height: 132)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            // Fades rather than clears when you lift your hands, so the shape
            // of what you played stays readable for a moment.
            .opacity(model.isSounding ? 1 : 0.55)
            .animation(.easeOut(duration: 0.35), value: model.isSounding)
    }

    // MARK: - Detail

    private var detail: some View {
        HStack(alignment: .top, spacing: 28) {
            column("NOTES") {
                if let chord = model.chord {
                    ForEach(Array(chord.spelledTones.enumerated()), id: \.offset) { _, tone in
                        HStack(spacing: 8) {
                            Text(tone.note.name(unicode: true))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(IslandTheme.primary)
                                .frame(width: 34, alignment: .leading)
                            Text(tone.interval.shortName)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(IslandTheme.tertiary)
                                .frame(width: 30, alignment: .leading)
                            Text(tone.interval.longName)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(IslandTheme.secondary)
                                .lineLimit(1)
                        }
                    }
                } else if !model.heldNotes.isEmpty {
                    // Not a chord, but still worth naming: which note, and where
                    // it sits in the key.
                    ForEach(model.heldNotes.sorted(), id: \.self) { note in
                        HStack(spacing: 8) {
                            Text(SpelledNote.natural(PitchClass(note),
                                                     preferFlats: model.key?.preferFlats ?? false)
                                .name(unicode: true))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(IslandTheme.primary)
                                .frame(width: 34, alignment: .leading)
                            Text(MIDINote.name(note))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(IslandTheme.tertiary)
                                .frame(width: 30, alignment: .leading)
                            Text(degreeDescription(of: note))
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(IslandTheme.secondary)
                                .lineLimit(1)
                        }
                    }
                } else {
                    Text("nothing held")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(IslandTheme.tertiary)
                }
            }

            column("ALSO READS AS") {
                if model.chord == nil {
                    Text(model.heldNotes.isEmpty ? "\u{2014}" : "not a named chord")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(IslandTheme.tertiary)
                } else if model.alternatives.isEmpty {
                    Text("unambiguous")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(IslandTheme.tertiary)
                } else {
                    ForEach(Array(model.alternatives.prefix(4).enumerated()), id: \.offset) { _, alt in
                        HStack(spacing: 8) {
                            Text(alt.chord.symbol(unicode: true))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(IslandTheme.secondary)
                                .frame(width: 86, alignment: .leading)
                                .lineLimit(1)
                            ConfidenceBar(value: alt.confidence, width: 44)
                        }
                    }
                }
            }

            column("SCALES THAT FIT") {
                let fits = model.scaleFits
                if fits.isEmpty {
                    Text("\u{2014}")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(IslandTheme.tertiary)
                }
                ForEach(Array(fits.prefix(5).enumerated()), id: \.offset) { _, fit in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(fit.root.name()) \(fit.scale.name)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(IslandTheme.primary)
                            .lineLimit(1)
                        Text(fit.scale.spelled(root: fit.root).map { $0.name() }.joined(separator: " "))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(IslandTheme.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        // Reserved height. Without it the columns grow and shrink with their
        // contents, so every chord change nudges everything below it -- which
        // reads as the window twitching each time you play.
        .frame(height: Self.detailHeight, alignment: .top)
    }

    /// Room for the longest column the detail area can show: six chord tones.
    private static let detailHeight: CGFloat = 190

    /// Where a lone note sits in the current key, in words.
    private func degreeDescription(of note: Int) -> String {
        guard let key = model.key else { return "" }
        let names = ["root", "2nd", "3rd", "4th", "5th", "6th", "7th"]
        if let degree = key.scaleDegree(of: PitchClass(note)), degree - 1 < names.count {
            return "\(names[degree - 1]) of \(key.name)"
        }
        return "outside \(key.name)"
    }

    @ViewBuilder
    private func column<Content: View>(_ title: String,
                                       @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(IslandTheme.tertiary)
                .tracking(0.8)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What the key colours mean. Four colours only earn their place if the
    /// reader is told what they are.
    @ViewBuilder
    private var legend: some View {
        if model.chord != nil {
            HStack(spacing: 16) {
                ForEach(Array(IslandTheme.roleLegend.enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(entry.color)
                            .frame(width: 16, height: 8)
                        Text(entry.label)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(IslandTheme.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().overlay(IslandTheme.hairline)
            HStack(spacing: 10) {
                Circle()
                    .fill(model.isSounding ? IslandTheme.diatonic : IslandTheme.tertiary)
                    .frame(width: 6, height: 6)
                Text(model.inputLabel)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(IslandTheme.secondary)
                    .lineLimit(1)

                if model.sustainDown {
                    Text("SUSTAIN")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(IslandTheme.background)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(IslandTheme.chromatic))
                }

                Spacer(minLength: 12)

                if !model.progression.isEmpty {
                    ProgressionStrip(model: model)
                        .frame(maxWidth: 460, alignment: .trailing)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }
}
