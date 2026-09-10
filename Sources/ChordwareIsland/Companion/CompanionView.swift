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
        Group {
            if model.isCompactLayout { compact } else { full }
        }
        .background {
            if model.displayMode.isTranslucent {
                // Overlay sits on top of whatever you are working in, so it has
                // to let some of it through and stop short of the window edge.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(IslandTheme.background.opacity(0.78))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .padding(6)
            } else {
                IslandTheme.background
            }
        }
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: model.displayMode)
    }

    private var full: some View {
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
    }

    /// The minimum needed to see and talk about what is being played.
    ///
    /// Deliberately the *same* keyboard as the companion view, at the same key
    /// size. Presentation mode is less interface, not a bigger one; blowing the
    /// keys up to fill a window turns the instrument into something that no
    /// longer looks like a piano.
    private var compact: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(model.displaySymbol)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(model.isSounding ? IslandTheme.primary : IslandTheme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .contentTransition(.numericText())
                if let numeral = model.romanNumeral {
                    Text(numeral.symbol(naming: model.naming))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(numeral.isDiatonic ? IslandTheme.diatonic : IslandTheme.chromatic)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let key = model.key {
                    Text(key.shortName(naming: model.naming))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(IslandTheme.tertiary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            keyboardView(height: 108)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    /// One keyboard, shared by every mode. Modes differ in what surrounds it,
    /// never in how the instrument itself is drawn.
    private func keyboardView(height: CGFloat) -> some View {
        MiniPiano(heldNotes: model.heldNotes,
                  lowNote: model.keyboardLowNote,
                  octaves: model.keyboardOctaves,
                  showsOctaveLabels: true,
                  namesHeldNotes: true,
                  chord: model.chord,
                  velocities: model.velocities,
                  naming: model.naming,
                  key: model.key,
                  usesRoleColors: model.roleColors)
            .frame(height: height)
            .opacity(model.isSounding ? 1 : 0.55)
            .animation(.easeOut(duration: 0.35), value: model.isSounding)
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
                    Text(numeral.symbol(naming: model.naming))
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .foregroundStyle(numeral.isDiatonic ? IslandTheme.diatonic : IslandTheme.chromatic)
                        .lineLimit(1)
                    Text(numeral.explanation ?? numeral.function.name)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(IslandTheme.tertiary)
                        .lineLimit(1)
                }
                if let key = model.key {
                    Text("key of \(key.name(naming: model.naming))")
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
        keyboardView(height: 132)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
    }

    // MARK: - Detail

    private var detail: some View {
        HStack(alignment: .top, spacing: 28) {
            column("NOTES") {
                if let chord = model.chord {
                    ForEach(Array(chord.spelledTones.enumerated()), id: \.offset) { _, tone in
                        HStack(spacing: 8) {
                            Text(model.naming.name(tone.note, in: model.key, unicode: true))
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
                            Text(model.naming.name(PitchClass(note), in: model.key, unicode: true))
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
                            Text(alt.chord.symbol(naming: model.naming, in: model.key, unicode: true))
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
                        // A scale's root is a note, not a degree of the key.
                        Text("\(fit.root.name()) \(fit.scale.name)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(IslandTheme.primary)
                            .lineLimit(1)
                        Text(fit.scale.spelled(root: fit.root, naming: model.naming, key: model.key)
                            .joined(separator: " "))
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
