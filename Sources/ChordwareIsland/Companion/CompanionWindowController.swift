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
