import AppKit
import SwiftUI

/// Owns the island window and drives its state from pointer position.
@MainActor
public final class IslandController {
    public let model: IslandModel
    public private(set) var geometry: ScreenGeometry

    private var window: NotchWindow?
    private var hostingView: PassthroughHostingView<IslandRootView>?
    private var movedMonitor: Any?
    private var clickMonitor: Any?
    private var toastTask: Task<Void, Never>?
    private var pinned = false

    /// Height of the window; the island never grows past this.
    private static let windowHeight: CGFloat = 420
    private static let windowWidth: CGFloat = 760

    public init(model: IslandModel, geometry: ScreenGeometry? = nil) {
        self.model = model
        self.geometry = geometry ?? ScreenGeometry.main
            ?? ScreenGeometry(notchWidth: 200, notchHeight: 32, isPhysical: false,
                              screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982))
    }

    public func start() {
        let screenFrame = geometry.screenFrame
        let frame = CGRect(
            x: screenFrame.midX - Self.windowWidth / 2,
            y: screenFrame.maxY - Self.windowHeight,
            width: Self.windowWidth,
            height: Self.windowHeight
        )

        let window = NotchWindow(contentRect: frame)
        let root = IslandRootView(model: model, geometry: geometry)
        let hosting = PassthroughHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: frame.size)
        window.contentView = hosting
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()

        self.window = window
        self.hostingView = hosting
        updateActiveRect()
        installMonitors()
    }

    public func stop() {
        if let movedMonitor { NSEvent.removeMonitor(movedMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        movedMonitor = nil
        clickMonitor = nil
        window?.orderOut(nil)
        window = nil
    }

    /// The island's rect in screen coordinates for the current state.
    private var islandScreenRect: CGRect {
        guard let window else { return .zero }
        let size = IslandRootView.size(for: model.state, geometry: geometry)
        let frame = window.frame
        return CGRect(x: frame.midX - size.width / 2,
                      y: frame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    private func updateActiveRect() {
        guard let hostingView, let window else { return }
        let screenRect = islandScreenRect
        hostingView.activeRect = CGRect(
            x: screenRect.minX - window.frame.minX,
            y: screenRect.minY - window.frame.minY,
            width: screenRect.width, height: screenRect.height
        )
    }

    private func installMonitors() {
        // Mouse-moved monitors need no accessibility permission (only keyboard
        // ones do), and a background non-activating panel does not reliably
        // receive SwiftUI hover events, so pointer tracking lives here.
        movedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in self?.pointerMoved() }
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            Task { @MainActor in self?.clickedOutside() }
        }
    }

    /// Hold a state regardless of the pointer, for screenshots and inspection.
    public func pinState(_ state: IslandState) {
        pinned = true
        withAnimation(IslandTheme.spring) { model.state = state }
        updateActiveRect()
    }

    private func pointerMoved() {
        guard window != nil, !pinned else { return }
        let inside = islandScreenRect.contains(NSEvent.mouseLocation)
        switch model.state {
        case .glance, .toast:
            if inside { setState(.expanded) }
        case .idle:
            // Hovering an empty island still opens it, so the app is reachable
            // when nothing is playing.
            if inside { setState(.expanded) }
        case .expanded:
            if !inside { setState(model.candidates.isEmpty ? .idle : .glance) }
        case .act:
            break
        }
        updateActiveRect()
    }

    private func clickedOutside() {
        guard model.state == .act, !islandScreenRect.contains(NSEvent.mouseLocation) else { return }
        setState(model.candidates.isEmpty ? .idle : .glance)
    }

    private func setState(_ state: IslandState) {
        guard model.state != state else { return }
        withAnimation(IslandTheme.spring) { model.state = state }
        updateActiveRect()
    }

    /// Show a momentary announcement, then fall back to whatever is playing.
    public func toast(_ toast: IslandToast, duration: Double = 2.2) {
        toastTask?.cancel()
        guard model.state == .glance || model.state == .idle else { return }
        setState(.toast(toast))
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            if case .toast = model.state {
                setState(model.candidates.isEmpty ? .idle : .glance)
            }
        }
    }

    /// Re-read the screen, for display changes and hot-plugged monitors.
    public func screenChanged() {
        guard let updated = ScreenGeometry.main else { return }
        geometry = updated
        stop()
        start()
    }
}
