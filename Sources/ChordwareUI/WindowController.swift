import AppKit
import Observation
import QuartzCore
import SwiftUI

/// Owns Chordware's window: a normal, resizable, movable one that can live on
/// whichever display you are actually looking at.
@MainActor
public final class WindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    private var isVisible: Bool { window?.isVisible ?? false }
    public private(set) var isAlwaysOnTop = false
    /// Header, keyboard and the status line, at the keyboard's natural key
    /// size. Content sizes, not frame sizes: the titlebar adds roughly thirty
    /// points on top, and treating one as the other clipped the keyboard off
    /// the bottom.
    private static let defaultContent = NSSize(width: 900, height: 272)
    private static let minimumContent = NSSize(width: 520, height: 212)

    /// The window frame, kept across launches. One owner, persisted -- AppKit's
    /// own autosave used to write the same thing from the other side and the
    /// two disagreed.
    ///
    /// Versioned: the window used to carry a panel under the keyboard and was
    /// six hundred points tall to fit it. A frame saved for that layout opens
    /// this one with a band of empty ground in it, so the old key is abandoned
    /// rather than migrated.
    private static let windowFrameKey = "ChordwareWindowFrame5"

    private var storedFrame: NSRect? {
        get {
            guard let values = UserDefaults.standard.array(forKey: Self.windowFrameKey) as? [Double],
                  values.count == 4 else { return nil }
            return NSRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }
        set {
            guard let newValue else {
                UserDefaults.standard.removeObject(forKey: Self.windowFrameKey)
                return
            }
            UserDefaults.standard.set([newValue.minX, newValue.minY, newValue.width, newValue.height],
                                      forKey: Self.windowFrameKey)
        }
    }

    public init(model: AppModel) {
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
            contentRect: NSRect(origin: .zero, size: Self.defaultContent),
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
        // AppKit releases a programmatically created window when it is closed,
        // and the red button really does close it -- our own close() only
        // orders it out. So clicking red left this controller holding a pointer
        // to a freed window, and the next thing to touch it segfaulted: the
        // reopen handler, or Control-Option-Command-C, which is the one way
        // back in when the status item is hidden behind another app's menu-bar
        // icon. The controller owns the window; nothing else may free it.
        window.isReleasedWhenClosed = false
        window.title = "Chordware"
        window.titlebarAppearsTransparent = true
        // AppKit's own title goes to the left the moment it has a subtitle,
        // and there is no switch to centre it. So it is hidden and drawn by
        // `installTitle` instead: still in the title bar, still naming the
        // window and the device, and centred over the keyboard. `title` stays
        // set for Mission Control and the Window menu.
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.black
        window.contentMinSize = Self.minimumContent
        window.delegate = self
        window.contentView = NSHostingView(rootView: ChordwareView(model: model))

        // Restore the frame we saved ourselves, and only if it is still usable
        // and still on a connected screen.
        if let saved = storedFrame, isUsable(saved) {
            window.setFrame(saved, display: false)
        } else {
            positionOnPreferredScreen(window)
        }

        self.window = window
        installTitle(in: window)
        trackStatus()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// The device, and the pedal, in the title bar.
    ///
    /// This was a strip of its own under the keyboard: twenty-four points of
    /// window spent on one line of grey text that is only ever read when
    /// something is wrong. A title bar is already there, already says what the
    /// window is, and is exactly where a Mac app puts what it is looking at.
    private var statusText: String {
        model.sustainDown ? model.inputLabel + "  \u{00B7}  sustain" : model.inputLabel
    }

    /// The centred title: "Chordware – device", on one line.
    private let titleLabel = PassThroughLabel(labelWithString: "")

    /// Put the title label in the title bar itself, centred on the window
    /// rather than on the space beside the traffic lights.
    private func installTitle(in window: NSWindow) {
        guard let titlebar = window.standardWindowButton(.closeButton)?.superview else { return }
        titleLabel.font = NSFont.titleBarFont(ofSize: 0)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        // Long device names truncate rather than push the window wider.
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titlebar.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: titlebar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: titlebar.centerYAnchor),
            // Clear of the traffic lights on both sides, so it stays centred.
            titleLabel.widthAnchor.constraint(lessThanOrEqualTo: titlebar.widthAnchor, constant: -160),
        ])
        updateTitleColor()
    }

    /// Dimmed when the window is not key, as AppKit's own title is.
    private func updateTitleColor() {
        titleLabel.textColor = (window?.isKeyWindow ?? false) ? .labelColor : .tertiaryLabelColor
    }

    public func windowDidBecomeKey(_ notification: Notification) { updateTitleColor() }
    public func windowDidResignKey(_ notification: Notification) { updateTitleColor() }

    /// Re-arms itself: an observation tracks one change and then stops, so
    /// without this the title would be correct exactly once.
    private func trackStatus() {
        guard window != nil else { return }
        withObservationTracking {
            titleLabel.stringValue = "Chordware \u{2013} " + statusText
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackStatus() }
        }
    }

    /// Ordered out, not released: the instance keeps the stored frame and the
    /// always-on-top setting across a close and reopen.
    public func close() {
        window?.orderOut(nil)
    }

    public func setAlwaysOnTop(_ onTop: Bool) {
        isAlwaysOnTop = onTop
        window?.level = onTop ? .floating : .normal
    }

    /// A frame is usable if it is big enough for the layout and at least
    /// partly on a screen that is still connected.
    private func isUsable(_ frame: NSRect) -> Bool {
        guard frame.width >= Self.minimumContent.width,
              frame.height >= Self.minimumContent.height else { return false }
        return NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
    }

    /// Open on a screen without a notch when there is one.
    ///
    /// If you have an external display, that is where you are looking while you
    /// play.
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

    /// What the green button zooms to: the window's natural size.
    ///
    /// AppKit's default is the whole screen, and that frame was then saved and
    /// restored on the next launch. Opened already at the "zoomed" size, the
    /// green button had no smaller size to go back to, and the window was stuck
    /// with a screen's height of empty black above the keys. Now zooming always
    /// brings it back to the size the layout is drawn for, top edge where it
    /// was.
    public func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        let size = window.frameRect(forContentRect: NSRect(origin: .zero, size: Self.defaultContent)).size
        var frame = NSRect(x: window.frame.midX - size.width / 2,
                           y: window.frame.maxY - size.height,
                           width: size.width, height: size.height)
        frame.origin.x = min(max(frame.minX, newFrame.minX), newFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, newFrame.minY), newFrame.maxY - frame.height)
        return frame
    }

    /// The green button resizes without a live resize, so it is saved here too.
    public func windowDidResize(_ notification: Notification) {
        guard let window, !window.inLiveResize,
              !window.styleMask.contains(.fullScreen) else { return }
        storedFrame = window.frame
    }

    public func windowDidEndLiveResize(_ notification: Notification) {
        guard let window else { return }
        storedFrame = window.frame
    }
}

/// A title that does not take the mouse, so the title bar under it still drags
/// the window and a double-click still zooms it.
final class PassThroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
