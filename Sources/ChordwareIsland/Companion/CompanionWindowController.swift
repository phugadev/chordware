import AppKit
import QuartzCore
import SwiftUI

/// Owns the companion window: a normal, resizable, movable window that can live
/// on whichever display you are actually looking at.
@MainActor
public final class CompanionWindowController: NSObject, NSWindowDelegate {
    private let model: IslandModel
    private var window: NSWindow?

    public var isVisible: Bool { window?.isVisible ?? false }
    public private(set) var isAlwaysOnTop = false
    /// Room for the keyboard at its natural key size, plus one header row.
    /// Content sizes, not frame sizes. The titlebar adds roughly thirty points
    /// on top, and treating one as the other clipped the keyboard off the
    /// bottom of presentation mode.
    /// The compact size the toggle snaps to. It has to clear what the layout
    /// actually needs -- header, keyboard and their padding -- or the keyboard
    /// is clipped off the bottom, which is how this went wrong before.
    private static let compactContent = NSSize(width: 900, height: 300)
    // Tall enough for the header, the keyboard and the full panel. The
    // header is taller than its type sizes suggest, because baseline
    // alignment between the symbol and the numeral adds the difference in
    // their ascents.
    private static let companionContent = NSSize(width: 900, height: 600)
    private static let companionMinimum = NSSize(width: 700, height: 520)
    private static let compactMinimum = NSSize(width: 600, height: 260)

    /// The companion frame, kept across launches.
    ///
    /// This used to live only in memory, and AppKit's own window autosave was
    /// writing the same thing from the other side. Switching to presentation
    /// let the autosave record the *compact* frame; quitting lost the way back;
    /// and relaunching restored a compact-sized window with the full layout in
    /// it. One owner, persisted.
    private static let companionFrameKey = "ChordwareCompanionFrame"

    private var storedCompanionFrame: NSRect? {
        get {
            guard let values = UserDefaults.standard.array(forKey: Self.companionFrameKey) as? [Double],
                  values.count == 4 else { return nil }
            return NSRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }
        set {
            guard let newValue else {
                UserDefaults.standard.removeObject(forKey: Self.companionFrameKey)
                return
            }
            UserDefaults.standard.set([newValue.minX, newValue.minY, newValue.width, newValue.height],
                                      forKey: Self.companionFrameKey)
        }
    }

    public init(model: IslandModel) {
        self.model = model
        super.init()
    }

    /// True when the window is both on screen and in front of you.
    ///
    /// `isVisible` alone is not enough: an accessory app's window can be
    /// ordered in but sitting behind the DAW, and a toggle that only checks
    /// visibility then *hides* it -- which is why bringing it up appeared to
    /// need two presses of the shortcut.
    public var isFrontmost: Bool { isVisible && NSApp.isActive }

    public func toggle() { isFrontmost ? close() : show() }

    public func show() {
        if let window {
            // Activate first. Ordering a window front from a background app
            // before the app itself is active can leave it behind everything.
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            // No .fullSizeContentView. With it, the hosting view covers the
            // title bar and AppKit's own drag region goes with it -- which is
            // why dragging the header never worked, through four attempts at
            // fixing it from the SwiftUI side. A real title bar is the one drag
            // region macOS guarantees. Transparent, untitled, over a black
            // window, it reads as the same strip of black it always did.
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Chordware"
        window.titlebarAppearsTransparent = true
        // Visible, like a Mac app's window has always been. It names what you
        // are looking at when the window is behind something, it gives the
        // header an obvious place to grab, and a hidden title over a title bar
        // that is already transparent was just an empty strip nobody could
        // tell was draggable.
        window.titleVisibility = .visible
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.black
        window.contentMinSize = Self.companionMinimum
        window.delegate = self
        window.contentView = NSHostingView(rootView: CompanionView(model: model))

        // Restore the companion frame we saved ourselves, never a compact one,
        // and only if it is still usable and still on a connected screen.
        if let saved = storedCompanionFrame, isUsable(saved) {
            window.setFrame(saved, display: false)
        } else {
            positionOnPreferredScreen(window)
        }

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    public func close() {
        window?.orderOut(nil)
    }

    /// Reshape the window for a display mode.
    ///
    /// Presentation is *less* interface, so the window shrinks too; keeping it
    /// full size and stretching the contents is how the keys ended up as slabs.
    public func apply(mode: DisplayMode) {
        guard let window else { return }
        if mode.usesCompactLayout {
            // Remember where companion was before shrinking, but never record a
            // compact frame as the companion one.
            if window.contentLayoutRect.height > Self.compactContent.height + 60 {
                storedCompanionFrame = window.frame
            }
            let current = window.frame
            let size = frameSize(forContent: Self.compactContent, in: window)
            // Grow downward from the existing top-left, so the window does not
            // appear to jump across the screen.
            let target = NSRect(x: current.minX,
                                y: current.maxY - size.height,
                                width: size.width,
                                height: size.height)
            window.contentMinSize = Self.compactMinimum
            resize(window, to: target)
        } else {
            window.contentMinSize = Self.companionMinimum
            // Grow to *something* valid whatever the window was left at. The
            // failure this replaces was a companion layout stuck in a window
            // too small to hold it, with no way back.
            let target = storedCompanionFrame.flatMap { isUsable($0) ? $0 : nil }
                ?? defaultCompanionFrame(near: window.frame)
            resize(window, to: target)
        }
    }


    /// Resize with no animation.
    private func resize(_ window: NSWindow, to frame: NSRect) {
        // Immediate. Animating the frame while the contents swap underneath
        // produced the bounce; the two cannot be synchronised without sharing a
        // layout, which is not worth what it costs.
        window.setFrame(frame, display: true)
    }

    public func setAlwaysOnTop(_ onTop: Bool) {
        isAlwaysOnTop = onTop
        window?.level = onTop ? .floating : .normal
    }

    /// A frame is usable if it is big enough for the companion layout and at
    /// least partly on a screen that is still connected.
    private func isUsable(_ frame: NSRect) -> Bool {
        guard frame.width >= Self.companionMinimum.width,
              frame.height >= Self.companionMinimum.height else { return false }
        return NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
    }

    /// Frame size that yields the requested content size, titlebar included.
    private func frameSize(forContent content: NSSize, in window: NSWindow) -> NSSize {
        window.frameRect(forContentRect: NSRect(origin: .zero, size: content)).size
    }

    private func defaultCompanionFrame(near current: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(current) }
            ?? NSScreen.screens.first { $0.safeAreaInsets.top == 0 }
            ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = window.map { frameSize(forContent: Self.companionContent, in: $0) }
            ?? Self.companionContent
        return NSRect(x: visible.midX - size.width / 2,
                      y: visible.midY - size.height / 2,
                      width: size.width, height: size.height)
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

    public func windowDidEndLiveResize(_ notification: Notification) {
        guard let window,
              window.contentLayoutRect.height > Self.compactContent.height + 60 else { return }
        storedCompanionFrame = window.frame
    }

    public func windowWillClose(_ notification: Notification) {
        // Keep the instance so the stored frame and the always-on-top setting
        // survive a close and reopen.
    }
}
