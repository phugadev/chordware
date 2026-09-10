import AppKit

/// Where the island should sit on a given screen.
///
/// Notched Macs report the notch indirectly: `safeAreaInsets.top` is its height,
/// and `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` are the usable strips
/// either side of it. Subtracting those from the screen width gives the notch
/// width without hardcoding a single model's dimensions.
public struct ScreenGeometry: Equatable, Sendable {
    /// Width of the physical notch, or of the drawn pill on screens without one.
    public let notchWidth: CGFloat
    /// Height of the physical notch, or the menu bar height as a stand-in.
    public let notchHeight: CGFloat
    /// False when this screen has no notch and the island is drawing its own.
    public let isPhysical: Bool
    public let screenFrame: CGRect

    /// Fallback pill size for screens with no notch — an external display, or
    /// any Mac before the notch existed. Roughly matches a 14-inch notch so the
    /// island feels the same on both.
    public static let virtualNotchSize = CGSize(width: 200, height: 32)

    public init(screen: NSScreen) {
        screenFrame = screen.frame
        let safeTop = screen.safeAreaInsets.top
        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        let measured = screen.frame.width - left - right

        // A notched screen reports a positive top inset *and* two auxiliary
        // areas that do not span the full width.
        if safeTop > 0, left > 0, right > 0, measured > 0, measured < screen.frame.width {
            notchWidth = measured
            notchHeight = safeTop
            isPhysical = true
        } else {
            notchWidth = Self.virtualNotchSize.width
            notchHeight = max(Self.virtualNotchSize.height, NSStatusBar.system.thickness)
            isPhysical = false
        }
    }

    /// Test seam: build a geometry without a real screen.
    public init(notchWidth: CGFloat, notchHeight: CGFloat, isPhysical: Bool, screenFrame: CGRect) {
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        self.isPhysical = isPhysical
        self.screenFrame = screenFrame
    }

    public static var main: ScreenGeometry? {
        NSScreen.main.map(ScreenGeometry.init(screen:))
    }

    /// The screen the island should open on.
    ///
    /// Prefers a screen that actually has a notch. `NSScreen.main` means "the
    /// screen with keyboard focus", so using it puts the island on whichever
    /// display happened to be focused at launch — which on a laptop plus an
    /// external monitor is a coin toss, and lands the notch UI on the monitor
    /// without a notch about half the time.
    public static var preferred: ScreenGeometry? {
        if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return ScreenGeometry(screen: notched)
        }
        return main
    }

    /// The notched screen, if the Mac has one.
    public static var notchedScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }

    /// The window rect for a given island content size, centred on the notch and
    /// pinned to the top of the screen.
    public func windowFrame(contentSize: CGSize) -> CGRect {
        let width = max(contentSize.width, notchWidth)
        let height = max(contentSize.height, notchHeight)
        return CGRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
    }
}
