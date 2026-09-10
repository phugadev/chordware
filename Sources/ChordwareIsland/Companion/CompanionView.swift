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

    // Sizes differ between modes; the structure does not.
    private var symbolSize: CGFloat { model.isCompactLayout ? 40 : 60 }
    private var numeralSize: CGFloat { model.isCompactLayout ? 22 : 38 }
    private var keyboardHeight: CGFloat { model.isCompactLayout ? 108 : 132 }

    /// Natural height of the panel below the keyboard.
    private static let panelHeight: CGFloat = 300

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(IslandTheme.hairline)
            keyboardView(height: keyboardHeight)
                .padding(.horizontal, model.isCompactLayout ? 16 : 20)
                .padding(.vertical, model.isCompactLayout ? 12 : 18)

            // The panel is *revealed by the window*, not swapped for another
            // view. Building a different tree per mode gives each its own view
            // identity, so SwiftUI cross-fades them -- the panel dissolves
            // while the window resizes underneath it, on a different curve.
            // Holding it at its natural height inside a flexible clipping frame
            // means shrinking the window slides it away instead.
            // The panel's height is driven by the mode, not by whatever space
            // happens to be left over. Leaving it to fill the remainder meant
            // presentation mode still had room for about forty points of it,
            // so the column headings showed under the keyboard.
            //
            // It hangs in an overlay rather than sitting in the stack because a
            // rigid `.frame(height:)` inside the layout is reported upward as a
            // *minimum*, and NSHostingView then refuses to let the window
            // shrink past it.
            Color.clear
                .frame(height: model.isCompactLayout ? 0 : Self.panelHeight)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .top) {
                    panel.frame(height: Self.panelHeight, alignment: .top)
                }
                .clipped()
            Spacer(minLength: 0)
        }
        // Anchor to the top and clip. Mid-resize the content is briefly taller
        // than the window, and a centred stack loses the same amount off both
        // ends -- which takes the chord name with it. Overflow has to fall off
        // the bottom, where the panel is, because that is the part being
        // dismissed.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .background(IslandTheme.background)
        .preferredColorScheme(.dark)
        .animation(IslandTheme.modeTransition, value: model.displayMode)
    }

    /// One header for both modes. Only the type sizes and two collapsing rows
    /// differ, so nothing has to move across the window when the mode changes.
    private var header: some View {
        // Baseline alignment between a 40-point symbol and a 22-point numeral
        // inflates the row by the difference in their ascents, which is how
        // presentation mode ended up with a header tall enough to clip the
        // keyboard. Compact centres a single row instead.
        HStack(alignment: model.isCompactLayout ? .center : .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                if hasSomethingToShow {
                    Text(model.displaySymbol)
                        .animatableFont(size: symbolSize)
                        .foregroundStyle(model.isSounding ? IslandTheme.primary : IslandTheme.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .contentTransition(.numericText())
                    if !model.isCompactLayout {
                        Text(model.displayDetail)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(IslandTheme.secondary)
                            .lineLimit(1)
                    }
                } else {
                    // An em dash set at sixty points is a grey slab, and reads
                    // as a broken element rather than as "nothing yet".
                    Text("play something")
                        .animatableFont(size: symbolSize * 0.45, weight: .medium)
                        .foregroundStyle(IslandTheme.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            if model.isCompactLayout {
                compactTrailing
            } else {
                expandedTrailing
            }
        }
        .padding(.horizontal, model.isCompactLayout ? 20 : 24)
        .padding(.top, model.isCompactLayout ? 12 : 20)
        .padding(.bottom, model.isCompactLayout ? 6 : 16)
    }

    /// Numeral and key on one line, so the header stays one row tall.
    private var compactTrailing: some View {
        HStack(spacing: 10) {
            if let numeral = model.romanNumeral {
                Text(numeral.symbol(naming: model.naming))
                    .animatableFont(size: numeralSize)
                    .foregroundStyle(numeral.isDiatonic ? IslandTheme.diatonic : IslandTheme.chromatic)
                    .lineLimit(1)
            }
            if let key = model.key {
                keyLabel(key, compact: true)
            }
        }
    }

    private var expandedTrailing: some View {
        VStack(alignment: .trailing, spacing: 4) {
                if let numeral = model.romanNumeral {
                    Text(numeral.symbol(naming: model.naming))
                        .animatableFont(size: numeralSize)
                        .foregroundStyle(numeral.isDiatonic ? IslandTheme.diatonic : IslandTheme.chromatic)
                        .lineLimit(1)
                    Text(numeral.explanation ?? numeral.function.name)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(IslandTheme.tertiary)
                        .lineLimit(1)
                }
                if let key = model.key {
                    keyLabel(key, compact: false)
                }
        }
    }

    /// The key, with a padlock when it was named rather than detected.
    private func keyLabel(_ key: Key, compact: Bool) -> some View {
        HStack(spacing: 4) {
            if model.lockedKey != nil {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(IslandTheme.tertiary)
            }
            Text(compact ? key.shortName(naming: model.naming)
                         : "key of \(key.name(naming: model.naming))")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(IslandTheme.secondary)
        }
    }

    /// Everything below the keyboard, at its natural height.
    private var panel: some View {
        VStack(spacing: 0) {
            Divider().overlay(IslandTheme.hairline)
            detail
            legend
            Spacer(minLength: 0)
            footer
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
