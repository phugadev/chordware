import AppKit
import SwiftUI

/// A hosting view that lets clicks through everywhere except the island itself.
///
/// The window spans the whole top strip of the screen so the island can grow
/// without resizing it mid-animation, which means most of it must be
/// transparent to the mouse or it would swallow clicks on the menu bar.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    /// The island's current rect, in this view's own (y-up) coordinates.
    var activeRect: CGRect = .zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        guard activeRect.contains(local) else { return nil }
        return super.hitTest(point)
    }
}

/// The island's window: borderless, transparent, above the menu bar, and
/// present on every Space including over a full-screen app.
public final class NotchWindow: NSPanel {
    public init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            // A non-activating panel can be clicked without stealing focus from
            // the DAW, which is the entire point of acting from the notch.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Never take key status away from whatever the player is working in.
        becomesKeyOnlyIfNeeded = true
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}
