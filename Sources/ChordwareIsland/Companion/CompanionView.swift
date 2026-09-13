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

    /// Below this much window, the panel is dropped and the chord grows.
    ///
    /// There used to be two layouts behind a mode switch. A mode is not what
    /// that was: it was "make the window small", and the window already does
    /// that. One tree that answers to its own height removes the toggle, the
    /// second header, the second keyboard call and the whole class of bug where
    /// two trees drift apart.
    private static let panelThreshold: CGFloat = 560

    /// Fixed heights, so nothing below the header can move as you play. A long
    /// chord symbol, a missing Roman numeral or an absent key would otherwise
    /// each change the height and nudge the keyboard.
    private static func headerHeight(compact: Bool) -> CGFloat { compact ? 140 : 128 }
    /// Less room means the chord should be *easier* to read, not harder: at a
    /// glance from a music stand, or across a room on a stream.
    private static func symbolSize(compact: Bool) -> CGFloat { compact ? 76 : 60 }

    public var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < Self.panelThreshold
            VStack(spacing: 0) {
                header(compact: compact)
                Divider().overlay(IslandTheme.hairline)
                keyboardView(height: keyboardHeight(in: proxy.size.height, compact: compact))
                    .padding(.horizontal, compact ? 16 : 20)
                    .padding(.vertical, compact ? 12 : 18)
                if !compact {
                    Divider().overlay(IslandTheme.hairline)
                    detail(height: Self.panelHeight(in: proxy.size.height))
                    footer
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .background(IslandTheme.background)
        .preferredColorScheme(.dark)
    }

    /// With the panel gone the keyboard takes the room it leaves, within
    /// bounds: unbounded it becomes a row of slabs, fixed it leaves a band of
    /// black under it at most window sizes.
    private func keyboardHeight(in available: CGFloat, compact: Bool) -> CGFloat {
        guard compact else { return 132 }
        let used = Self.headerHeight(compact: true) + 20 + 8 + 1 + 24
        // Capped: a 49-key keyboard across 900 points has keys about 18 wide,
        // and past roughly ten times that they stop reading as piano keys and
        // start reading as slabs. A window between the two useful sizes keeps
        // some black under the keyboard, which is the lesser fault.
        return min(max(100, available - used), 200)
    }

    /// A grid, not two columns of whatever height they happen to be.
    ///
    /// Rows are aligned across the header: the chord symbol shares a baseline
    /// with the Roman numeral, and the spoken name shares one with the
    /// function. The key sits on a third row of its own. Laid out as two
    /// free-standing columns the left one had two lines and the right had
    /// three, so the left's second line landed *between* the right's two and
    /// the lower half read as three staggered baselines.
    ///
    /// Every row is always present, at the same sizes, whether or not anything
    /// is playing. Swapping the empty state for fewer or smaller lines makes
    /// the header shorter when idle and taller when sounding, so every key
    /// press shoves the keyboard and everything under it up and down.
    /// Centred: the chord is the thing you are looking at, and everything
    /// else is a caption for it. Split left and right it read as a form with
    /// two empty fields whenever nothing was playing.
    ///
    /// Every row is always present, at the same sizes, whether or not anything
    /// is playing. Swapping the empty state for fewer or smaller lines makes
    /// the header shorter when idle and taller when sounding, so every key
    /// press shoves the keyboard and everything under it up and down.
    private func header(compact: Bool) -> some View {
        VStack(spacing: 2) {
            Text(model.romanNumeral?.symbol(naming: model.naming) ?? "\u{2014}")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(numeralColor)
                .lineLimit(1)
            Text(model.displaySymbol)
                .font(.system(size: Self.symbolSize(compact: compact),
                              weight: .semibold, design: .rounded))
                .foregroundStyle(headerSymbolColor)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .contentTransition(.numericText())
            Text(model.displayDetail)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(IslandTheme.secondary)
                .lineLimit(1)
            functionAndKey
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.headerHeight(compact: compact), alignment: .top)
        .padding(.horizontal, 24)
        .padding(.top, compact ? 14 : 18)
        .padding(.bottom, compact ? 8 : 14)
    }

    /// What the Roman numeral means, and the key it means it in, on one line.
    ///
    /// These were two rows -- the function, then the key under it -- which gave
    /// the right column a third row the left column had nothing to match. They
    /// are one statement anyway: `I` means nothing except *in G major*. The
    /// explanation takes the function's place whenever there is one to give, so
    /// the line always says the most useful thing it can and never grows.
    private var functionAndKey: Text {
        var line = Text("")
        if let numeral = model.romanNumeral {
            line = line + Text((numeral.explanation ?? numeral.function.name) + " \u{00B7} ")
                .foregroundColor(IslandTheme.tertiary)
        }
        if model.lockedKey != nil {
            line = line + Text(Image(systemName: "lock.fill"))
                .foregroundColor(IslandTheme.tertiary) + Text(" ")
        }
        let name = model.key.map { "in \($0.name(naming: model.naming))" } ?? "no key yet"
        return line + Text(name)
            .foregroundColor(model.key == nil ? IslandTheme.tertiary : IslandTheme.secondary)
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
            // Claim the keyboard's own clicks so it does not drag the window.
            // Grabbing a piano and having the window move is wrong, and the
            // keys are the one part of this view that will want clicks of its
            // own later.
            .contentShape(Rectangle())
    }

    /// What is left after the header, the keyboard and the footer have taken
    /// theirs. Reserving a fixed block instead made the panel overflow the
    /// moment its contents needed more than the block -- five scales did -- and
    /// the overflow drew straight through the footer.
    ///
    /// This changes with the window, never with what is played, so nothing
    /// moves while you are playing.
    private static func panelHeight(in available: CGFloat) -> CGFloat {
        max(120, available - (128 + 18 + 14) - 1 - (132 + 36) - 1 - 55)
    }

    /// How many scales fit in the room the panel actually has.
    ///
    /// A scale row is a name over its notes: measured, 35 points. Guessing 29
    /// put a fifth row half through the footer rule.
    private static func scaleRows(forPanel height: CGFloat) -> Int {
        max(2, min(5, Int((height - 36 - 18) / 35)))
    }

    private func detail(height: CGFloat) -> some View {
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
                            // Whether the tone is actually under a finger is
                            // already said by the colour; spelling it out in
                            // words was diagnostics, not teaching.
                            Text(tone.interval.longName)
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

            column("SCALES THAT FIT") {
                let fits = model.scaleFits
                if fits.isEmpty {
                    Text("\u{2014}")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(IslandTheme.tertiary)
                }
                ForEach(Array(fits.prefix(Self.scaleRows(forPanel: height)).enumerated()), id: \.offset) { _, fit in
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
        .frame(height: height, alignment: .top)
        .clipped()
    }

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
            // Fixed. The strip only renders once something has been played, and
            // its chips grow a second line once a key is established, so the
            // footer used to get taller twice -- shoving the panel, the
            // keyboard and the header up by eight points each time. The row is
            // now as tall as its tallest contents whether they are there or not.
            .frame(height: 30)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }
}
