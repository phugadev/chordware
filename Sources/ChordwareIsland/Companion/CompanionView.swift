import ChordwareCore
import SwiftUI

/// The whole app: a black readout saying what you are playing, and the keyboard
/// you are playing it on.
///
/// Laid out after ChordWatch, because ChordWatch got the shape right: the chord
/// is the thing you look up at, so it gets a panel of its own and most of the
/// window; the keys are the thing you glance down at, so they are a strip along
/// the bottom and no taller than they need to be to be read.
public struct CompanionView: View {
    @Bindable public var model: IslandModel

    public init(model: IslandModel) {
        self.model = model
    }

    /// A strip, not a wall.
    ///
    /// A white key is roughly two and a half times as tall as it is wide at the
    /// size this is drawn, which is what a keyboard looks like from where you
    /// sit at one. Given the whole window it grew to six times its width, which
    /// is a photograph of a piano rather than a control you glance at, and it
    /// pushed the chord -- the part you actually read -- into a corner.
    private static let keyboardHeight: CGFloat = 88
    private static let statusHeight: CGFloat = 24

    /// The chord is drawn to the panel it is in, so dragging the window short
    /// shrinks it instead of running it through the keyboard.
    private static func symbolSize(inPanel height: CGFloat) -> CGFloat {
        min(84, max(34, height * 0.38))
    }

    private var isPlaying: Bool { !model.heldNotes.isEmpty }

    public var body: some View {
        VStack(spacing: 0) {
            readout
            MiniPiano(heldNotes: model.heldNotes,
                      lowNote: model.keyboardLowNote,
                      octaves: model.keyboardOctaves,
                      showsOctaveLabels: true,
                      namesHeldNotes: true,
                      chord: model.chord,
                      key: model.key)
                // Edge to edge. The rounded card, its lit border and its drop
                // shadow were three ways of saying "this is a piano" to
                // something that already looks like one.
                .frame(height: Self.keyboardHeight)
                // Claim the keyboard's own clicks so it does not drag the window.
                .contentShape(Rectangle())
            status
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IslandTheme.background)
        .preferredColorScheme(.dark)
        // A chord change is a musical event, so let it read as one. Short
        // enough that it never lags behind the hands.
        .animation(.easeOut(duration: 0.12), value: model.displaySymbol)
    }

    /// Black, and empty when your hands are off the keys.
    private var readout: some View {
        GeometryReader { proxy in
        ZStack {
            IslandTheme.panel
            VStack(spacing: 6) {
                Text(model.displaySymbol)
                    .font(.system(size: Self.symbolSize(inPanel: proxy.size.height),
                                  weight: .semibold, design: .rounded))
                    .foregroundStyle(isPlaying ? IslandTheme.played : IslandTheme.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    .contentTransition(.numericText())
                Text(model.displayDetail)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(IslandTheme.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 130)
            // The other ways to read the same keys, quietly. `A C E G` is Am7
            // and it is C6/A, and which one you meant is context the notes do
            // not carry -- so the display should not pretend to be sure.
            VStack(alignment: .trailing, spacing: 1) {
                ForEach(Array(model.alternatives.prefix(2).enumerated()), id: \.offset) { _, other in
                    Text(other.chord.symbol(naming: .letters, in: model.key, unicode: true))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(IslandTheme.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(14)
            // Which inversion, because on a keyboard that is a shape under your
            // hand rather than a fact about the notes.
            inversions
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(14)
        }
        // Nothing escapes the panel and draws over the keys, whatever the
        // window is dragged to.
        .clipped()
        }
    }

    private static let inversionNames = ["root", "1st", "2nd", "3rd"]

    private var inversions: some View {
        HStack(spacing: 10) {
            ForEach(Array(Self.inversionNames.enumerated()), id: \.offset) { index, name in
                let active = isPlaying && model.chord?.inversion == index
                Text(name)
                    .font(.system(size: 11, weight: active ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(active ? IslandTheme.played : IslandTheme.tertiary)
            }
        }
    }

    /// Not music, but the difference between "nothing is happening" and "the
    /// app is broken". A stuck pedal is otherwise invisible and looks exactly
    /// like the display refusing to let go of a chord.
    private var status: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isPlaying ? IslandTheme.played : IslandTheme.tertiary)
                .frame(width: 5, height: 5)
            Text(model.inputLabel)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(IslandTheme.tertiary)
                .lineLimit(1)
            if model.sustainDown {
                Text("SUSTAIN")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(IslandTheme.played)
            }
            Spacer(minLength: 0)
        }
        .frame(height: Self.statusHeight)
        .padding(.horizontal, 12)
    }
}
