import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers
import ChordwareCore
import ChordwareEngine
import ChordwareIsland

/// Entry point. Uses `@main` rather than a `main.swift` so the whole launch
/// path is main-actor isolated, which AppKit requires and top-level code in
/// Swift 6 no longer assumes.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Accessory policy: no Dock icon, no menu bar item. The island is the app.
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private let model = IslandModel()
    private var controller: IslandController?
    private var bridge: SessionBridge?
    private var demo: DemoDriver?
    private var companion: CompanionWindowController?
    private var menuBar: MenuBarController?
    private var companionHotKey: GlobalHotKey?
    private var presentationHotKeyRef: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments

        // `--probe` reports what the island measured on the attached displays.
        if arguments.contains("--probe") {
            for screen in NSScreen.screens {
                let g = ScreenGeometry(screen: screen)
                let kind = g.isPhysical ? "physical notch" : "no notch (pill fallback)"
                print("\(screen.localizedName): \(Int(g.screenFrame.width))x\(Int(g.screenFrame.height))"
                      + "  \(kind)  notch \(Int(g.notchWidth))x\(Int(g.notchHeight))")
                for state in [IslandState.idle, .glance, .expanded, .act] {
                    let size = IslandRootView.size(for: state, geometry: g)
                    print("    \(state)  \(Int(size.width))x\(Int(size.height))")
                }
            }
            exit(0)
        }

        // `--render <dir>` writes every island state to PNG and exits, which is
        // how the layout is reviewed without a live window.
        if let index = arguments.firstIndex(of: "--render"), index + 1 < arguments.count {
            let directory = URL(fileURLWithPath: arguments[index + 1])
            let geometry = ScreenGeometry.preferred
                ?? ScreenGeometry(notchWidth: 200, notchHeight: 32, isPhysical: false,
                                  screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982))
            do {
                let written = try IslandRenderer.renderAll(to: directory, geometry: geometry)
                for url in written { print(url.path) }
            } catch {
                FileHandle.standardError.write(Data("render failed: \(error)\n".utf8))
                exit(1)
            }
            exit(0)
        }

        // `--virtual-notch` forces the fallback pill so the non-notched layout
        // can be checked on a machine that has a notch.
        var geometry = arguments.contains("--screen-main")
            ? ScreenGeometry.main : ScreenGeometry.preferred
        if arguments.contains("--virtual-notch"), let real = geometry {
            geometry = ScreenGeometry(
                notchWidth: ScreenGeometry.virtualNotchSize.width,
                notchHeight: ScreenGeometry.virtualNotchSize.height,
                isPhysical: false,
                screenFrame: real.screenFrame
            )
        }

        let controller = IslandController(model: model, geometry: geometry)
        controller.start()
        self.controller = controller

        let companion = CompanionWindowController(model: model)
        self.companion = companion

        // A background app with no Dock icon needs a status item, or there is
        // no way to open the window, change input, or even quit.
        let menuBar = MenuBarController(actions: .init(
            openCompanion: { companion.toggle() },
            toggleAlwaysOnTop: { companion.setAlwaysOnTop(!companion.isAlwaysOnTop) },
            setDisplayMode: { [weak self] mode in
                guard let self else { return }
                self.model.displayMode = mode
                companion.show()
                companion.apply(mode: mode)
            },
            setKey: { [weak self] key in
                self?.bridge?.session.lockedKey = key
                self?.model.lockedKey = key
            },
            exportPerformance: { [weak self] in self?.exportPerformance() },
            clearPerformance: { [weak self] in self?.bridge?.session.recorder.clear() },
            chooseMIDI: { [weak self] in self?.bridge?.session.source = .midi },
            chooseAudio: { [weak self] in self?.bridge?.session.source = .audio },
            togglePassthrough: { [weak self] in
                guard let out = self?.bridge?.session.midiOut else { return }
                out.passthrough.toggle()
                if !out.passthrough { out.allNotesOff() }
            },
            resetProgression: { [weak self] in
                self?.model.progression.clear()
                self?.model.clearChord()
            },
            panic: { [weak self] in
                self?.bridge?.session.panic()
                self?.model.clearChord()
            },
            resetKeyboardRange: { [weak self] in self?.bridge?.resetKeyboardRange() },
            setNaming: { [weak self] naming in self?.model.naming = naming },
            toggleRoleColors: { [weak self] in self?.model.roleColors.toggle() }
        ))
        menuBar.currentSourceIsAudio = { [weak self] in self?.bridge?.session.source == .audio }
        menuBar.currentAlwaysOnTop = { companion.isAlwaysOnTop }
        menuBar.currentPassthrough = { [weak self] in self?.bridge?.session.midiOut.passthrough ?? false }
        menuBar.currentDisplayMode = { [weak self] in self?.model.displayMode ?? .companion }
        menuBar.currentLockedKey = { [weak self] in self?.model.lockedKey }
        menuBar.currentPerformanceCount = { [weak self] in self?.bridge?.session.recorder.count ?? 0 }
        menuBar.currentNaming = { [weak self] in self?.model.naming ?? .letters }
        menuBar.currentRoleColors = { [weak self] in self?.model.roleColors ?? true }
        menuBar.currentChordSummary = { [weak self] in
            guard let chord = self?.model.chord else { return nil }
            guard let key = self?.model.key else { return chord.symbol() }
            return chord.symbol() + "  \u{00B7}  " + key.shortName
        }
        menuBar.install()
        self.menuBar = menuBar

        // Control-Option-Command-C. The status item is unreachable on a
        // notched MacBook with a busy menu bar, so there has to be another way
        // in that does not depend on menu bar real estate.
        let hotKey = GlobalHotKey { companion.toggle() }
        hotKey.register(keyCode: UInt32(kVK_ANSI_C),
                        modifiers: UInt32(cmdKey | optionKey | controlKey))
        companionHotKey = hotKey

        // Cycles companion -> compact -> overlay -> companion, so all three are
        // reachable without the menu bar, which can be unreachable behind the
        // notch on a busy menu bar.
        let modeHotKey = GlobalHotKey { [weak self] in
            guard let self else { return }
            let order = DisplayMode.allCases
            let next = order[(order.firstIndex(of: self.model.displayMode).map { $0 + 1 } ?? 0) % order.count]
            self.model.displayMode = next
            companion.show()
            companion.apply(mode: next)
        }
        modeHotKey.register(keyCode: UInt32(kVK_ANSI_P),
                            modifiers: UInt32(cmdKey | optionKey | controlKey))
        presentationHotKeyRef = modeHotKey

        if arguments.contains("--window") { companion.show() }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in controller.screenChanged() }
        }

        // `--demo` replays a scripted progression, which is how the island is
        // tuned and screenshotted. Everything else runs on live input.
        if arguments.contains("--demo") {
            let driver = DemoDriver(model: model, controller: controller)
            driver.start(stepping: arguments.contains("--step"))
            demo = driver
        } else if !arguments.contains("--no-input") {
            let bridge = SessionBridge(model: model, controller: controller)
            if arguments.contains("--audio") { bridge.session.source = .audio }
            if let index = arguments.firstIndex(of: "--audio-device"), index + 1 < arguments.count {
                bridge.session.source = .audio
                bridge.session.startAudio(deviceID: arguments[index + 1])
            }
            bridge.start()
            self.bridge = bridge
        }

        // `--animate` walks the states on a timer with the real spring, so the
        // transition can be captured frame by frame without synthesising
        // pointer events (which needs an accessibility permission the app
        // itself does not require).
        if arguments.contains("--animate") {
            Task { @MainActor in
                let walk: [IslandState] = [.glance, .expanded, .act, .expanded, .glance]
                while !Task.isCancelled {
                    for state in walk {
                        controller.pinState(state)
                        try? await Task.sleep(for: .milliseconds(1400))
                    }
                }
            }
        }

        // `--state <name>` pins the island open so a given state can be
        // screenshotted or inspected without chasing it with the pointer.
        if let index = arguments.firstIndex(of: "--state"), index + 1 < arguments.count {
            let name = arguments[index + 1]
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                self.demo?.stop()
                switch name {
                case "idle": self.model.state = .idle
                case "glance": self.model.state = .glance
                case "expanded": self.model.state = .expanded
                case "act": self.model.state = .act
                case "toast":
                    self.model.state = .toast(IslandToast(kind: .cadence,
                                                          title: "authentic (V\u{2013}I)",
                                                          detail: "G7 \u{2192} Cmaj7"))
                default: break
                }
                controller.pinState(self.model.state)
            }
        }
    }

    /// Write everything played so far to a file the player chooses.
    private func exportPerformance() {
        guard let data = bridge?.session.performanceData() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.midi]
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        panel.nameFieldStringValue = "Chordware \(stamp.string(from: Date()).replacingOccurrences(of: ":", with: "."))"
        panel.title = "Save Performance"
        // The app has no Dock icon, so the panel needs bringing forward itself.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Release anything still sounding so a quit mid-chord cannot leave a
        // note hanging in the DAW.
        bridge?.stop()
        controller?.stop()
    }
}
