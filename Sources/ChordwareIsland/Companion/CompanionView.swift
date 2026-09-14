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
    /// Defaulted, so the window is one call and the alternatives are one
    /// argument.
    public var palette: IslandTheme.Palette
    /// TRIAL. Where the last few chords go, if anywhere.
    public var history: HistoryPlacement
    /// TRIAL.
    public var namesIncludeOctave: Bool

    public enum HistoryPlacement: Sendable {
        /// As it ships today.
        case none
        /// Along the foot of the black readout, above the keys.
        case inReadout
        /// Its own strip between the keyboard and the device line.
        case ownStrip
    }

    public init(model: IslandModel,
                palette: IslandTheme.Palette = IslandTheme.standard,
                history: HistoryPlacement = .none,
                namesIncludeOctave: Bool = false) {
        self.model = model
        self.palette = palette
        self.history = history
        self.namesIncludeOctave = namesIncludeOctave
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
        min(76, max(32, height * 0.42))
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
                      key: model.key,
                      palette: palette,
                      namesIncludeOctave: namesIncludeOctave)
                // Edge to edge. The rounded card, its lit border and its drop
                // shadow were three ways of saying "this is a piano" to
                // something that already looks like one.
                .frame(height: Self.keyboardHeight)
                // Claim the keyboard's own clicks so it does not drag the window.
                .contentShape(Rectangle())
            if history == .ownStrip { historyStrip.padding(.top, 6) }
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
    ///
    /// Only the chord and its name. The other readings of the same keys used to
    /// sit in one corner -- Am7 and C6/A for the same four notes -- and which
    /// inversion it was in the other. Both were true and neither was read: they
    /// are only visible once you are already looking at the chord name, which is
    /// the moment you have the least attention to spare.
    private var readout: some View {
        GeometryReader { proxy in
            ZStack {
                IslandTheme.panel
                VStack(spacing: 6) {
                    Text(model.displaySymbol)
                        .font(.system(size: Self.symbolSize(inPanel: proxy.size.height),
                                      weight: .semibold, design: .rounded))
                        .foregroundStyle(isPlaying ? palette.chord : IslandTheme.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.35)
                        .contentTransition(.numericText())
                    Text(model.displayDetail)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(IslandTheme.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 24)
                if history == .inReadout {
                    historyStrip
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 10)
                }
            }
            // Nothing escapes the panel and draws over the keys, whatever the
            // window is dragged to.
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    /// TRIAL: the last few chords, oldest on the left.
    ///
    /// The one thing actually missed from the panel that was taken out: you
    /// play something good, look down, and it is already gone. Fixed width per
    /// chord so the row does not reflow as names change length, and the most
    /// recent one is the only one at full strength -- the rest are there to be
    /// read deliberately, not to compete with the chord you are playing now.
    private var historyStrip: some View {
        let events = model.progression.tail(8)
        return HStack(spacing: 6) {
            Spacer(minLength: 0)
            ForEach(events) { event in
                Text(event.chord.symbol(naming: .letters, in: model.key, unicode: true))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(event.id == events.last?.id
                                     ? palette.chord : IslandTheme.tertiary)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
            }
            Spacer(minLength: 0)
        }
        .frame(height: 24)
        .padding(.horizontal, 12)
    }

    /// Not music, but the difference between "nothing is happening" and "the
    /// app is broken". A stuck pedal is otherwise invisible and looks exactly
    /// like the display refusing to let go of a chord.
    private var status: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isPlaying ? palette.live : IslandTheme.tertiary)
                .frame(width: 5, height: 5)
            Text(model.inputLabel)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(IslandTheme.tertiary)
                .lineLimit(1)
            if model.sustainDown {
                Text("SUSTAIN")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(palette.chord)
            }
            Spacer(minLength: 0)
        }
        .frame(height: Self.statusHeight)
        .padding(.horizontal, 12)
    }
}
