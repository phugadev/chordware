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

    private var hasSomethingToShow: Bool { model.chord != nil || !model.heldNotes.isEmpty }

    private var headerSymbolColor: Color {
        guard hasSomethingToShow else { return IslandTheme.tertiary }
        return model.isSounding ? IslandTheme.primary : IslandTheme.secondary
    }

    /// Fixed, so nothing below the header can move.
    ///
    /// Belt and braces alongside keeping both lines present: a long chord
    /// symbol, a missing Roman numeral or an absent key would otherwise each
    /// change the height and nudge the keyboard.
    private static let headerHeight: CGFloat = 100
    private static let compactHeaderHeight: CGFloat = 52

    public var body: some View {
        Group {
            if model.isCompactLayout { presentation } else { full }
        }
        .background(IslandTheme.background)
        .preferredColorScheme(.dark)
        // No animation. A window resize and a layout swap cannot be made to
        // move as one thing without merging the layouts, and merging them cost
        // four regressions last time. An instant change is honest.
        .animation(nil, value: model.displayMode)
    }

    /// Everything, with the panel taking whatever space is left and the footer
    /// sitting on the bottom edge.
    ///
    /// This was briefly rebuilt as a single tree shared with presentation mode,
    /// so switching between them could animate as one movement. Sharing forced
    /// the panel to a fixed height; the fixed height forced a taller window;
    /// the taller window pushed the footer off the bottom; and the fixed height
    /// was then reported upward as the window's minimum. Three regressions for
    /// a smoother quarter-second. The layouts are separate again.
    private var full: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(IslandTheme.hairline)
            keyboardView(height: 132)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            Divider().overlay(IslandTheme.hairline)
            detail
            legend
            Spacer(minLength: 0)
            footer
        }
    }

    /// The least that still communicates what is being played.
    private var presentation: some View {
        VStack(spacing: 0) {
            compactHeader
            Divider().overlay(IslandTheme.hairline)
            keyboardView(height: 108)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            // Both lines are always present, at the same sizes, whether or not
            // anything is playing. Swapping the empty state for a single
            // smaller line makes the header shorter when idle and taller when
            // sounding, so every key press shoves the keyboard and everything
            // under it up and down.
            VStack(alignment: .leading, spacing: 4) {
                Text(model.displaySymbol)
                    .font(.system(size: 60, weight: .semibold, design: .rounded))
                    .foregroundStyle(headerSymbolColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .contentTransition(.numericText())
                Text(model.displayDetail)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(IslandTheme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            expandedTrailing
        }
        .frame(height: Self.headerHeight, alignment: .top)
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .windowDragHandle()
    }

    /// One row: chord on the left, numeral and key on the right.
    private var compactHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(model.displaySymbol)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(headerSymbolColor)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .contentTransition(.numericText())
            Spacer(minLength: 12)
            compactTrailing
        }
        .frame(height: Self.compactHeaderHeight)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .windowDragHandle()
    }

    /// Numeral and key on one line, so the compact header stays one row tall.
    private var compactTrailing: some View {
        HStack(spacing: 10) {
            Text(model.romanNumeral?.symbol(naming: model.naming) ?? "\u{2014}")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(numeralColor)
                .lineLimit(1)
            keyLabel(model.key, compact: true)
        }
    }

    /// Three lines, always, whatever is playing.
    ///
    /// Rendering them only when there is something to say makes the column
    /// shorter when idle and taller when sounding, so the whole right-hand side
    /// jumps every time a chord is recognised.
    private var expandedTrailing: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(model.romanNumeral?.symbol(naming: model.naming) ?? "\u{2014}")
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .foregroundStyle(numeralColor)
                .lineLimit(1)
            Text(model.romanNumeral.map { $0.explanation ?? $0.function.name } ?? " ")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(IslandTheme.tertiary)
                .lineLimit(1)
            keyLabel(model.key, compact: false)
        }
    }

    private var numeralColor: Color {
        guard let numeral = model.romanNumeral else { return IslandTheme.tertiary }
        return numeral.isDiatonic ? IslandTheme.diatonic : IslandTheme.chromatic
    }

    /// The key, with a padlock when it was named rather than detected.
    private func keyLabel(_ key: Key?, compact: Bool) -> some View {
        HStack(spacing: 4) {
            if model.lockedKey != nil {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(IslandTheme.tertiary)
            }
            Text(key.map { compact ? $0.shortName(naming: model.naming)
                                   : "key of \($0.name(naming: model.naming))" } ?? "no key yet")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(key == nil ? IslandTheme.tertiary : IslandTheme.secondary)
        }
    }


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

    private var detail: some View {
        HStack(alignment: .top, spacing: 28) {
            column("NOTES") {
                if let chord = model.chord {
                    ForEach(Array(chord.spelledTones.enumerated()), id: \.offset) { _, tone in
                        // A chord can be named without every tone being played:
                        // the fifth is optional, so A + C reads as Am. Showing
                        // the implied E as solidly as the two real notes makes
                        // the keyboard look like it is missing a key.
                        let sounding = model.heldNotes.contains {
                            PitchClass($0) == tone.note.pitchClass
                        }
                        HStack(spacing: 8) {
                            Text(model.naming.name(tone.note, in: model.key, unicode: true))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(sounding ? IslandTheme.primary : IslandTheme.tertiary)
                                .frame(width: 34, alignment: .leading)
                            Text(tone.interval.shortName)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(IslandTheme.tertiary)
                                .frame(width: 30, alignment: .leading)
                            Text(sounding ? tone.interval.longName
                                          : tone.interval.longName + " \u{00B7} not played")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(sounding ? IslandTheme.secondary : IslandTheme.tertiary)
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
    /// What the key colours mean.
    ///
    /// Always occupies its height, so appearing and vanishing cannot nudge what
    /// is under it, and only shown when the colours it explains are in use.
    private var legend: some View {
        HStack(spacing: 16) {
            if model.roleColors, model.chord != nil {
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
            }
            Spacer(minLength: 0)
        }
        .frame(height: 14)
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
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
