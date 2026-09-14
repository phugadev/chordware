import ChordwareCore
import SwiftUI

/// The whole app: what you are playing, and the keys you are playing it on.
///
/// There used to be a panel under the keyboard listing the chord's tones, six
/// scales that fit it, and the last eight chords. All of it was true and none
/// of it was being read, because when your hands are on the keys you look at
/// one thing. The scales, the Roman numerals, the key analysis and the
/// progression are all still in the engine and all still reachable from the
/// `chordware` CLI; they are just not in the way any more.
public struct CompanionView: View {
    @Bindable public var model: IslandModel

    public init(model: IslandModel) {
        self.model = model
    }

    /// Fixed, so nothing moves while you play. A long chord symbol, a missing
    /// name or an absent device would otherwise each change a height and nudge
    /// the keyboard.
    private static let headerHeight: CGFloat = 112
    private static let symbolSize: CGFloat = 72
    private static let statusHeight: CGFloat = 34
    /// A white key is about 23mm by 145mm. Past roughly six and a half times
    /// its own width it stops looking like a piano key and starts looking like
    /// a slab.
    private static let keyboardCap: CGFloat = 264

    private var symbolColor: Color {
        if model.chord == nil, model.heldNotes.isEmpty { return IslandTheme.tertiary }
        return model.isSounding ? IslandTheme.primary : IslandTheme.secondary
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            // Dragged taller than the keyboard's cap, the slack goes around the
            // keyboard rather than under it: the chord stays at the top where
            // you look for it and the device line stays at the bottom.
            Spacer(minLength: 0)
            keyboard
            Spacer(minLength: 0)
            status
        }
        // Fills the window, so the ground is painted to the edges. Left to its
        // natural height the stack stopped where the status line did and the
        // rest of a tall window was whatever was behind it.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IslandTheme.background)
        .preferredColorScheme(.dark)
        // A chord change is a musical event, so let it read as one. Short
        // enough that it never lags behind the hands.
        .animation(.easeOut(duration: 0.13), value: model.chord?.symbol())
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(model.displaySymbol)
                .font(.system(size: Self.symbolSize, weight: .semibold, design: .rounded))
                .foregroundStyle(symbolColor)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .contentTransition(.numericText())
            Text(model.displayDetail)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(IslandTheme.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.headerHeight)
        .padding(.horizontal, 24)
    }

    private var keyboard: some View {
        MiniPiano(heldNotes: model.heldNotes,
                  lowNote: model.keyboardLowNote,
                  octaves: model.keyboardOctaves,
                  showsOctaveLabels: true,
                  namesHeldNotes: true,
                  chord: model.chord,
                  velocities: model.velocities,
                  key: model.key)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(IslandTheme.surfaceHigh)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(IslandTheme.edgeLight, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.55), radius: 10, y: 4)
            )
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
            // Takes every point the header and the status line do not need,
            // between a floor that keeps it visible and a cap that keeps it a
            // piano.
            .frame(minHeight: 130, maxHeight: Self.keyboardCap)
            // Claim the keyboard's own clicks so it does not drag the window.
            .contentShape(Rectangle())
    }

    /// Not music, but the difference between "nothing is happening" and "the
    /// app is broken". A stuck pedal is otherwise invisible and looks exactly
    /// like the display refusing to let go of a chord.
    private var status: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.isSounding ? IslandTheme.diatonic : IslandTheme.tertiary)
                .frame(width: 6, height: 6)
            Text(model.inputLabel)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(IslandTheme.tertiary)
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
            Spacer(minLength: 0)
        }
        .frame(height: Self.statusHeight)
        .padding(.horizontal, 24)
    }
}
