import ChordwareCore
import SwiftUI

/// The island itself. Sits at the top of an otherwise transparent window,
/// centred on the notch, and morphs between states with one spring.
public struct IslandRootView: View {
    @Bindable public var model: IslandModel
    public let geometry: ScreenGeometry
    public var onStateChange: ((IslandState) -> Void)?
    /// Freezes the reveal part-way, for reviewing what the transition looks
    /// like mid-flight. Nil in normal use.
    public var detailHeightOverride: CGFloat?

    public init(model: IslandModel, geometry: ScreenGeometry,
                onStateChange: ((IslandState) -> Void)? = nil,
                detailHeightOverride: CGFloat? = nil) {
        self.model = model
        self.geometry = geometry
        self.onStateChange = onStateChange
        self.detailHeightOverride = detailHeightOverride
    }

    private var revealedHeight: CGFloat {
        detailHeightOverride ?? Self.detailHeight(for: model.state)
    }

    private var notchWidth: CGFloat { geometry.notchWidth }
    private var notchHeight: CGFloat { geometry.notchHeight }

    /// Side panel width in the collapsed states, either side of the notch.
    private static let glanceSide: CGFloat = 132
    /// Fixed heights for the two halves of the detail area. The container's
    /// height animates between multiples of these and clips, which is what
    /// makes the panel appear to grow rather than fade in.
    public static let expandedDetailHeight: CGFloat = 164
    public static let actDetailHeight: CGFloat = 172

    /// How much of the detail stack is currently revealed.
    public static func detailHeight(for state: IslandState) -> CGFloat {
        switch state {
        case .idle, .glance, .toast: return 0
        case .expanded: return expandedDetailHeight
        case .act: return expandedDetailHeight + actDetailHeight
        }
    }

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
            return CGSize(width: notchWidth + 360, height: notchHeight)
        case .expanded:
            return CGSize(width: max(468, notchWidth + 260),
                          height: notchHeight + detailHeight(for: state))
        case .act:
            return CGSize(width: max(532, notchWidth + 320),
                          height: notchHeight + detailHeight(for: state))
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            content
                .frame(width: size.width,
                       height: geometry.notchHeight + revealedHeight)
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

    /// One persistent view tree for every state.
    ///
    /// Building a different tree per state — the obvious `switch` — gives each
    /// state a distinct view identity, so SwiftUI cross-fades between them and
    /// the panel appears to dissolve into place rather than open. Keeping the
    /// strip and the detail stack alive at all times and animating the clip
    /// height instead means the panel is physically revealed from under the
    /// notch, and the chord symbol in the strip never blinks.
    private var content: some View {
        VStack(spacing: 0) {
            NotchStrip(notchWidth: notchWidth, totalWidth: size.width, height: notchHeight) {
                stripLeading
            } trailing: {
                stripTrailing
            }

            VStack(spacing: 0) {
                ExpandedDetail(model: model)
                    .frame(height: Self.expandedDetailHeight, alignment: .top)
                ActDetail(model: model)
                    .frame(height: Self.actDetailHeight, alignment: .top)
                    // Rows below the clip must not take clicks meant for the
                    // apps behind the island.
                    .allowsHitTesting(model.state == .act)
                Spacer(minLength: 0)
            }
            .frame(height: revealedHeight, alignment: .top)
            .clipped()
        }
    }

    @ViewBuilder
    private var stripLeading: some View {
        switch model.state {
        case .idle: Color.clear
        case .toast(let toast): ToastLeading(toast: toast)
        default: GlanceLeft(model: model)
        }
    }

    @ViewBuilder
    private var stripTrailing: some View {
        switch model.state {
        case .idle: Color.clear
        case .toast(let toast): ToastTrailing(toast: toast)
        default: GlanceRight(model: model)
        }
    }
}

/// A row that keeps its content clear of the physical notch.
///
/// Every state needs this for its top strip, not just the collapsed ones — an
/// expanded panel still has the notch cut out of its first ~32 points.
struct NotchStrip<Leading: View, Trailing: View>: View {
    let notchWidth: CGFloat
    let totalWidth: CGFloat
    let height: CGFloat
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    /// Each side gets a concrete width rather than `maxWidth: .infinity`.
    /// A flexible frame lets a long label — "backdoor (bVII7-I)" — push past
    /// the island's edge instead of truncating inside it.
    private var sideWidth: CGFloat { max(0, (totalWidth - notchWidth) / 2) }

    var body: some View {
        HStack(spacing: 0) {
            leading
                .padding(.trailing, 12)
                .frame(width: sideWidth, alignment: .trailing)
                .clipped()
            Color.clear.frame(width: notchWidth)
            trailing
                .padding(.leading, 12)
                .frame(width: sideWidth, alignment: .leading)
                .clipped()
        }
        .frame(height: height)
    }
}

struct GlanceLeft: View {
    var model: IslandModel

    var body: some View {
        if model.isSounding || model.chord != nil {
            Text(model.displaySymbol)
                .font(IslandTheme.chordFont(16))
                .foregroundStyle(IslandTheme.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .truncationMode(.tail)
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
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
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
                .minimumScaleFactor(0.7)
                .truncationMode(.tail)
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
