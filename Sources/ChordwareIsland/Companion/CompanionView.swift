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
    private static func headerHeight(compact: Bool) -> CGFloat { compact ? 100 : 96 }
    /// Less room means the chord should be *easier* to read, not harder: at a
    /// glance from a music stand, or across a room on a stream.
    private static func symbolSize(compact: Bool) -> CGFloat { compact ? 76 : 60 }

    public var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < Self.panelThreshold
            VStack(spacing: 0) {
                header(compact: compact)
                // Dragged to a height between the two the toggle snaps to, the
                // compact layout runs out of things to put under the keyboard
                // before it runs out of window. Centred in what is left rather
                // than dropped against the header, so the slack reads as margin
                // instead of as the layout having stopped early.
                if compact { Spacer(minLength: 0) }
                keyboardCard(compact: compact)
                if compact { Spacer(minLength: 0) }
                if !compact {
                    // Second claim on the space, and it only ever asks for what
                    // its rows need.
                    detail(rows: Self.scaleRows(inWindow: proxy.size.height))
                        .layoutPriority(2)
                    // Only reached once the keyboard has hit its cap, which
                    // takes a window taller than anyone opens by accident.
                    Spacer(minLength: 0)
                    footer
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .background(IslandTheme.background)
        .preferredColorScheme(.dark)
        // A chord change is a musical event, so let it read as one. Short
        // enough that it never lags behind the hands.
        .animation(.easeOut(duration: 0.13), value: model.chord?.symbol())
    }

    /// The keyboard takes every point the header, the panel and the footer do
    /// not need, between bounds.
    ///
    /// It used to be pinned at 132 points with the panel given the remainder,
    /// and the panel could not use it: it lists at most six scales, so past a
    /// certain window height it was a card with ninety points of nothing under
    /// the last row -- while the instrument the app is *for* was drawn at half
    /// the height it could have been. Priority, not arithmetic: the panel asks
    /// for what its rows need and the keyboard is handed the rest, so there is
    /// no measurement here to get wrong.
    ///
    /// The cap is a proportion, not a taste. A white key is about 23mm by
    /// 145mm, so past roughly six and a half times its own width it stops
    /// looking like a piano key and starts looking like a slab.
    private static let keyboardCap: CGFloat = 264
    private static let compactKeyboardCap: CGFloat = 236

    private func keyboardCard(compact: Bool) -> some View {
        keyboardView()
            .padding(compact ? 8 : 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(IslandTheme.surfaceHigh)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(IslandTheme.edgeLight, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.55), radius: 10, y: 4)
            )
            .padding(.horizontal, compact ? 14 : 18)
            .padding(.vertical, compact ? 10 : 14)
            // A floor as well as a cap: squeezed to nothing by a panel that
            // wanted more than the window had, the keyboard would vanish and
            // take the point of the window with it.
            .frame(minHeight: compact ? 136 : 158,
                   maxHeight: compact ? Self.compactKeyboardCap : Self.keyboardCap)
            .layoutPriority(1)
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
            // The rows still hold their height when there is nothing to put in
            // them -- the layout must not move -- but they draw nothing.
            if model.lockedKey != nil {
                Text(model.isEmpty ? " " : (model.romanNumeral?.symbol(naming: model.naming) ?? "\u{2014}"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(numeralColor)
                    .lineLimit(1)
            }
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
            if model.lockedKey != nil {
                Group {
                    if model.isEmpty { Text(" ") } else { functionAndKey }
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.headerHeight(compact: compact), alignment: .top)
        .padding(.horizontal, 24)
        .padding(.top, compact ? 14 : 18)
        .padding(.bottom, compact ? 8 : 14)
        .frame(maxWidth: .infinity)
        // A gradient, not a band. Flat, the well sat a few percent off the
        // ground: too little to read as a recess and just enough to leave a
        // hard horizontal seam across the window under the chord name.
        .background(
            LinearGradient(colors: [IslandTheme.well, IslandTheme.background],
                           startPoint: .top, endPoint: .bottom)
        )
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


    private func keyboardView() -> some View {
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
            // Claim the keyboard's own clicks so it does not drag the window.
            // Grabbing a piano and having the window move is wrong, and the
            // keys are the one part of this view that will want clicks of its
            // own later.
            .contentShape(Rectangle())
    }

    /// How many scales to list. Six is all the chord-to-scale map returns.
    ///
    /// This used to be a function of the panel's own height, back when the
    /// panel was handed whatever the keyboard did not want. It is the other way
    /// round now, so the question is how much window there is.
    private static func scaleRows(inWindow height: CGFloat) -> Int {
        height >= 640 ? 6 : 5
    }

    private func detail(rows: Int) -> some View {
        // One height in every state. The rows below each hold their own, so
        // the panel is the same size whether the chord fits six scales or two
        // -- otherwise the panel shrinks, the keyboard grows to fill what it
        // gave up, and the instrument changes size under your hands as you
        // play, which is the one thing this layout is not allowed to do.
        ZStack {
            columns(rows: rows).opacity(model.isEmpty ? 0 : 1)
            if model.isEmpty { emptyMessage }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(IslandTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(IslandTheme.edgeLight, lineWidth: 1)
                )
        )
        .padding(.horizontal, 18)
        .clipped()
    }

    /// One sentence saying what this space is for, rather than three row
    /// headings standing over nothing.
    private var emptyMessage: some View {
        Text("play a chord to see its notes and the scales that fit")
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(IslandTheme.tertiary)
            .frame(maxWidth: .infinity)
    }

    /// Measured against the type they hold, and fixed, so no row can change
    /// the panel's height by having more or less to say.
    private static let notesRowHeight: CGFloat = 20
    private static let scaleRowHeight: CGFloat = 16
    private static let recentRowHeight: CGFloat = 24

    /// Rows, not columns.
    ///
    /// Three labelled columns meant every answer was a narrow strip with a lot
    /// of air around it, and the notes needed six rows to say what fits on one.
    /// A label and its content on a line reads faster and leaves the space for
    /// the thing that actually needs it -- the scales.
    private func columns(rows: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            notesRow
            scalesBlock(rows: rows)
            recentRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The chord's tones on one line, and which inversion it is.
    ///
    /// A tone the chord is named for but nobody is holding -- the fifth of a
    /// two-note minor, say -- is dimmed rather than labelled, so the line stays
    /// a line.
    private var notesRow: some View {
        HStack(spacing: 10) {
            rowLabel("NOTES")
            if let chord = model.chord {
                ForEach(Array(chord.spelledTones.enumerated()), id: \.offset) { _, tone in
                    let sounding = model.heldNotes.contains {
                        PitchClass($0) == tone.note.pitchClass
                    }
                    HStack(spacing: 3) {
                        Text(model.naming.name(tone.note, in: model.key, unicode: true))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(sounding ? IslandTheme.primary : IslandTheme.tertiary)
                        Text(tone.interval.shortName)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(IslandTheme.tertiary)
                    }
                }
            } else if !model.heldNotes.isEmpty {
                ForEach(model.heldNotes.sorted(), id: \.self) { note in
                    Text(model.naming.name(PitchClass(note), in: model.key, unicode: true))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(IslandTheme.primary)
                }
            }
            Spacer(minLength: 8)
            if let inversion = model.chord?.inversion, inversion > 0 {
                Text(Self.inversionName(inversion))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(IslandTheme.secondary)
            }
        }
        .lineLimit(1)
        .frame(height: Self.notesRowHeight)
    }

    private static func inversionName(_ inversion: Int) -> String {
        let ordinals = ["", "1st", "2nd", "3rd", "4th", "5th"]
        guard inversion < ordinals.count else { return "\(inversion)th inversion" }
        return "\(ordinals[inversion]) inversion"
    }

    /// The scales, each one a name and its notes on the same line.
    private func scalesBlock(rows: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            rowLabel("SCALES")
            VStack(alignment: .leading, spacing: 5) {
                let fits = model.scaleFits
                // Always `rows` rows, filled or not. A chord that fits two
                // scales must leave the panel the same height as one that fits
                // six, or the keyboard above moves every time you change chord.
                ForEach(0..<rows, id: \.self) { index in
                    HStack(spacing: 10) {
                        if index < fits.count {
                            let fit = fits[index]
                            // A scale's root is a note, so it is written the
                            // way every other note on screen is written.
                            // Hard-coding letters here put "D Minor
                            // Pentatonic" over "Re Fa Sol La Do" -- the same
                            // root spelled two ways on one line.
                            Text("\(model.naming.name(fit.root, in: model.key, unicode: true)) \(fit.scale.name)")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(IslandTheme.primary)
                                .frame(width: 190, alignment: .leading)
                            Text(fit.scale.spelled(root: fit.root, naming: model.naming,
                                                   key: model.key).joined(separator: " "))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(IslandTheme.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    .lineLimit(1)
                    .frame(height: Self.scaleRowHeight)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// What was played just before this, lifted out of the footer where it was
    /// competing with the device name for the same strip.
    private var recentRow: some View {
        HStack(spacing: 10) {
            rowLabel("RECENT")
            ProgressionStrip(model: model)
                .frame(maxWidth: 520, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(height: Self.recentRowHeight)
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(IslandTheme.tertiary)
            .tracking(0.8)
            .frame(width: 52, alignment: .leading)
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

                // How sure the detector is. Worth saying quietly, because an
                // ambiguous voicing reads as a wrong answer otherwise.

            }
            // Fixed, so nothing in it can change the height of everything above.
            .frame(height: 16)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }
}
