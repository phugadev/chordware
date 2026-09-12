import AppKit
import SwiftUI

/// A transparent grab area that moves the window it is in.
///
/// `isMovableByWindowBackground` only starts a drag when the mouse-down lands on
/// a view that does not consume it, and SwiftUI consumes everything. Worse, a
/// `fullSizeContentView` window puts the hosting view over the title bar too, so
/// even the strip beside the traffic lights is dead. What is left is a window
/// that drags from wherever SwiftUI happens to have laid out nothing -- which
/// reads as a window that moves sometimes, from places that make no sense.
///
/// The header is the natural place to grab a window and holds nothing you can
/// click, so it becomes the handle. The traffic lights sit in a sibling view
/// above the hosting view and keep their own clicks regardless.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
        /// Double-clicking a title bar zooms or minimises, depending on the
        /// system setting. A handle that stands in for the title bar should do
        /// the same thing rather than swallow it.
        override func mouseUp(with event: NSEvent) {
            guard event.clickCount == 2 else { return super.mouseUp(with: event) }
            window?.performZoom(nil)
        }
    }
}

extension View {
    /// Make this region drag the window, the way a title bar would.
    ///
    /// The handle reaches up into the safe area on purpose. SwiftUI insets its
    /// content below the title bar, so without this the strip beside the
    /// traffic lights -- the most obvious place in the world to grab a window --
    /// is the one part that stays dead.
    func windowDragHandle() -> some View {
        overlay(WindowDragHandle().ignoresSafeArea(edges: .top))
    }
}
