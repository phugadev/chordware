import ChordwareCore
import SwiftUI

/// The island itself. Sits at the top of an otherwise transparent window,
/// centred on the notch, and morphs between states with one spring.
public struct IslandRootView: View {
    @Bindable public var model: IslandModel
    public let geometry: ScreenGeometry
    public var onStateChange: ((IslandState) -> Void)?

    public init(model: IslandModel, geometry: ScreenGeometry,
                onStateChange: ((IslandState) -> Void)? = nil) {
        self.model = model
        self.geometry = geometry
        self.onStateChange = onStateChange
    }

    private var notchWidth: CGFloat { geometry.notchWidth }
    private var notchHeight: CGFloat { geometry.notchHeight }

    /// Side panel width in the collapsed states, either side of the notch.
    private static let glanceSide: CGFloat = 132

    public var size: CGSize { Self.size(for: model.state, geometry: geometry) }

    /// The island's on-screen size for a state. Static so the window controller
    /// can compute the same rect for hit-testing without rendering.
    public static func size(for state: IslandState, geometry: ScreenGeometry) -> CGSize {
        let notchWidth = geometry.notchWidth, notchHeight = geometry.notchHeight
        switch state {
        case .idle:
            return CGSize(width: notchWidth, height: notchHeight)
        case .glance:
            return CGSize(width: notchWidth + Self.glanceSide * 2, height: notchHeight)
        case .toast:
            return CGSize(width: notchWidth + 300, height: notchHeight)
        case .expanded:
            return CGSize(width: max(468, notchWidth + 260), height: notchHeight + 164)
        case .act:
            return CGSize(width: max(532, notchWidth + 320), height: notchHeight + 194)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            content
                .frame(width: size.width, height: size.height)
                .background(shape.fill(IslandTheme.background))
                .clipShape(shape)
                .overlay(
                    // A hairline on the lower edges only; the top edge is the
                    // screen bezel and must stay invisible.
                    shape.stroke(IslandTheme.hairline, lineWidth: 0.5)
                        .opacity(model.state == .idle ? 0 : 1)
                )
                .contentShape(shape)
                .onTapGesture {
                    withAnimation(IslandTheme.spring) {
                        model.state = model.state == .act ? .expanded : .act
                    }
                }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(IslandTheme.spring, value: model.state)
        .onChange(of: model.state) { _, new in onStateChange?(new) }
    }

    private var shape: AnyShape {
        geometry.isPhysical
            ? AnyShape(NotchShape(topRadius: 9, bottomRadius: model.state == .idle ? 9 : 20))
            : AnyShape(PillShape(cornerRadius: model.state == .idle ? 10 : 20))
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            Color.clear
        case .glance:
            NotchStrip(notchWidth: notchWidth, height: notchHeight) {
                GlanceLeft(model: model)
            } trailing: {
                GlanceRight(model: model)
            }
        case .toast(let toast):
            NotchStrip(notchWidth: notchWidth, height: notchHeight) {
                ToastLeading(toast: toast)
            } trailing: {
                ToastTrailing(toast: toast)
            }
        case .expanded:
            VStack(spacing: 0) {
                NotchStrip(notchWidth: notchWidth, height: notchHeight) {
                    GlanceLeft(model: model)
                } trailing: {
                    GlanceRight(model: model)
                }
                ExpandedDetail(model: model)
            }
        case .act:
            VStack(spacing: 0) {
                NotchStrip(notchWidth: notchWidth, height: notchHeight) {
                    GlanceLeft(model: model)
                } trailing: {
                    GlanceRight(model: model)
                }
                ActDetail(model: model)
            }
        }
    }
}

/// A row that keeps its content clear of the physical notch.
///
/// Every state needs this for its top strip, not just the collapsed ones — an
/// expanded panel still has the notch cut out of its first ~32 points.
struct NotchStrip<Leading: View, Trailing: View>: View {
    let notchWidth: CGFloat
    let height: CGFloat
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
            Color.clear.frame(width: notchWidth)
            trailing
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
        }
        .frame(height: height)
    }
}

struct GlanceLeft: View {
    var model: IslandModel

    var body: some View {
        if let chord = model.chord {
            Text(chord.symbol(unicode: true))
                .font(IslandTheme.chordFont(16))
                .foregroundStyle(IslandTheme.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        } else {
            Text(model.inputLabel)
                .font(IslandTheme.labelFont(10))
                .foregroundStyle(IslandTheme.tertiary)
                .lineLimit(1)
        }
    }
}

struct GlanceRight: View {
    var model: IslandModel

    var body: some View {
        HStack(spacing: 6) {
            if let numeral = model.romanNumeral {
                Text(numeral.symbol)
                    .font(IslandTheme.labelFont(12))
                    .foregroundStyle(numeral.isDiatonic ? IslandTheme.diatonic : IslandTheme.chromatic)
                    .lineLimit(1)
            }
            if let key = model.key {
                if model.romanNumeral != nil {
                    Circle().fill(IslandTheme.tertiary).frame(width: 2.5, height: 2.5)
                }
                Text(key.shortName)
                    .font(IslandTheme.labelFont(10))
                    .foregroundStyle(IslandTheme.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct ToastLeading: View {
    let toast: IslandToast
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: toast.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(IslandTheme.accent)
            Text(toast.title)
                .font(IslandTheme.chordFont(13))
                .foregroundStyle(IslandTheme.primary)
                .lineLimit(1)
        }
    }
}

struct ToastTrailing: View {
    let toast: IslandToast
    var body: some View {
        Text(toast.detail ?? "")
            .font(IslandTheme.labelFont(10))
            .foregroundStyle(IslandTheme.secondary)
            .lineLimit(1)
    }
}
