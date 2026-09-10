import SwiftUI

/// The island silhouette: square against the top of the screen, rounded at the
/// bottom, and — the part that matters — *inverse*-rounded at the top, so the
/// panel appears to flow out of the screen edge rather than to be pasted on top
/// of it. Without the top fillets this reads as a floating black rectangle.
public struct NotchShape: Shape {
    public var topRadius: CGFloat
    public var bottomRadius: CGFloat

    public init(topRadius: CGFloat = 8, bottomRadius: CGFloat = 14) {
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
    }

    /// Animate the corner radii along with everything else during a morph.
    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    public func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        // Keep the radii sane for small rects so the shape never self-intersects.
        let top = min(topRadius, w / 4, h)
        let bottom = min(bottomRadius, (w - 2 * top) / 2, h - top)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top-left shoulder, curving down into the body.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        // Top-right shoulder.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

/// A pill for screens with no notch, so an external display behaves the same.
public struct PillShape: Shape {
    public var cornerRadius: CGFloat
    public init(cornerRadius: CGFloat = 16) { self.cornerRadius = cornerRadius }

    public func path(in rect: CGRect) -> Path {
        // Square along the screen edge, rounded everywhere else.
        let r = min(cornerRadius, rect.height / 2, rect.width / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - r),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
