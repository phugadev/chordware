import AppKit
import SwiftUI

/// Owns the companion window: a normal, resizable, movable window that can live
/// on whichever display you are actually looking at.
@MainActor
public final class CompanionWindowController: NSObject, NSWindowDelegate {
    private let model: IslandModel
    private var window: NSWindow?

    public var isVisible: Bool { window?.isVisible ?? false }
    public private(set) var isAlwaysOnTop = false
    private var expandedFrame: NSRect?

    /// Room for the keyboard at its natural key size, plus one header row.
    private static let compactSize = NSSize(width: 810, height: 236)

    public init(model: IslandModel) {
        self.model = model
        super.init()
    }

    public func toggle() { isVisible ? close() : show() }

    public func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Chordware"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.black
        window.minSize = NSSize(width: 700, height: 520)
        window.delegate = self
        window.contentView = NSHostingView(rootView: CompanionView(model: model))
        // Remembers where the user put it, including which display.
        window.setFrameAutosaveName("ChordwareCompanion")

        if window.frame.origin == .zero { positionOnPreferredScreen(window) }

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func close() {
        window?.orderOut(nil)
    }

    /// Shrink to the keyboard and one line of text, or restore.
    ///
    /// Presentation mode is *less* interface, so the window has to shrink too.
    /// Keeping it full size and stretching the contents is how the keys ended
    /// up as slabs.
    public func setCompact(_ compact: Bool) {
        guard let window else { return }
        if compact {
            if expandedFrame == nil { expandedFrame = window.frame }
            let current = window.frame
            // Grow downward from the existing top-left, so the window does not
            // appear to jump across the screen.
            let target = NSRect(x: current.minX,
                                y: current.maxY - Self.compactSize.height,
                                width: Self.compactSize.width,
                                height: Self.compactSize.height)
            window.minSize = NSSize(width: 520, height: 180)
            window.setFrame(target, display: true, animate: true)
        } else {
            window.minSize = NSSize(width: 700, height: 520)
            if let expandedFrame {
                window.setFrame(expandedFrame, display: true, animate: true)
            }
            expandedFrame = nil
        }
    }

    public func setAlwaysOnTop(_ onTop: Bool) {
        isAlwaysOnTop = onTop
        window?.level = onTop ? .floating : .normal
    }

    /// Open on a screen without a notch when there is one.
    ///
    /// If you have an external display, that is where you are looking while you
    /// play — the built-in screen is the one with the island on it already.
    private func positionOnPreferredScreen(_ window: NSWindow) {
        let external = NSScreen.screens.first { $0.safeAreaInsets.top == 0 }
        let screen = external ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        ))
    }

    public func windowWillClose(_ notification: Notification) {
        // Keep the instance so the frame autosave and always-on-top setting
        // survive a close/reopen.
    }
}
