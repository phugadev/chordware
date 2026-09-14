import AppKit
import ChordwareCore
import SwiftUI

/// The whole app: a black readout saying what you are playing, and the keyboard
/// you are playing it on.
///
/// Laid out after ChordWatch, because ChordWatch got the shape right: the chord
/// is the thing you look up at, so it gets a panel of its own and most of the
/// window; the keys are the thing you glance down at, so they are a strip along
/// the bottom and no taller than they need to be to be read.
public struct ChordwareView: View {
    @Bindable public var model: AppModel
    /// Defaulted, so the window is one call and the alternatives are one
    /// argument.
    public var palette: Theme.Palette
    public init(model: AppModel, palette: Theme.Palette = Theme.standard) {
        self.model = model
        self.palette = palette
    }

    /// A strip, not a wall.
    ///
    /// A white key is roughly two and a half times as tall as it is wide at the
    /// size this is drawn, which is what a keyboard looks like from where you
    /// sit at one. Given the whole window it grew to six times its width, which
    /// is a photograph of a piano rather than a control you glance at, and it
    /// pushed the chord -- the part you actually read -- into a corner.
    private static let keyboardHeight: CGFloat = 88

    /// The chord is drawn to the panel it is in, so dragging the window short
    /// shrinks it instead of running it through the keyboard.
    private static func symbolSize(inPanel height: CGFloat) -> CGFloat {
        min(76, max(32, height * 0.42))
    }

    private var isPlaying: Bool { !model.shownNotes.isEmpty }

    public var body: some View {
        VStack(spacing: 0) {
            readout
            MiniPiano(heldNotes: model.shownNotes,
                      lowNote: model.keyboardLowNote,
                      octaves: model.keyboardOctaves,
                      showsOctaveLabels: true,
                      namesHeldNotes: true,
                      chord: model.shownChord,
                      key: model.key,
                      palette: palette)
                // Edge to edge. The rounded card, its lit border and its drop
                // shadow were three ways of saying "this is a piano" to
                // something that already looks like one.
                .frame(height: Self.keyboardHeight)
                // Claim the keyboard's own clicks so it does not drag the
                // window. The device name and the pedal live in the title bar;
                // everything between the title bar and the keys is the readout.
                .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
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
                Theme.panel
                VStack(spacing: 6) {
                    Text(model.displaySymbol)
                        .font(.system(size: Self.symbolSize(inPanel: proxy.size.height),
                                      weight: .semibold, design: .rounded))
                        .foregroundStyle(isPlaying ? palette.chord : Theme.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.35)
                        .contentTransition(.numericText())
                    Text(model.displayDetail)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 24)
                historyStrip
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 10)
            }
            // Nothing escapes the panel and draws over the keys, whatever the
            // window is dragged to.
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    /// The last few chords, oldest on the left.
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
                let inspected = model.inspecting?.id == event.id
                let latest = event.id == events.last?.id && model.inspecting == nil
                Button {
                    model.inspect(event)
                } label: {
                    Text(event.chord.symbol(naming: .letters, in: model.key, unicode: true))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(inspected ? Theme.panel
                                         : (latest ? palette.chord : Theme.tertiary))
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(inspected ? palette.chord
                                                   : Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
                // A pointing hand, so the strip is discoverable without a label
                // saying "click me". `pointerStyle` would be the one line for
                // this and it is macOS 15 only.
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .help("Show this chord on the keyboard")
            }
            Spacer(minLength: 0)
        }
        .frame(height: 24)
        .padding(.horizontal, 12)
    }

}
