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
        // Accessory policy: no Dock icon. Chordware sits beside a DAW and a
        // screen recording; it has a status item and a window, and neither
        // wants a bouncing icon in the Dock or a slot in Command-Tab.
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private let model = IslandModel()
    private var bridge: SessionBridge?
    private var demo: DemoDriver?
    private var companion: CompanionWindowController?
    private var menuBar: MenuBarController?
    private var companionHotKey: GlobalHotKey?
    private var presentationHotKeyRef: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments

        // `--render <dir>` writes the window's layout to PNG and exits, which
        // is how it is reviewed without anything on screen.
        if let index = arguments.firstIndex(of: "--render"), index + 1 < arguments.count {
            let directory = URL(fileURLWithPath: arguments[index + 1])
            do {
                let written = try IslandRenderer.renderAll(to: directory)
                for url in written { print(url.path) }
            } catch {
                FileHandle.standardError.write(Data("render failed: \(error)\n".utf8))
                exit(1)
            }
            exit(0)
        }

        let companion = CompanionWindowController(model: model)
        self.companion = companion

        // A background app with no Dock icon needs a status item, or there is
        // no way to open the window, change input, or even quit.
        let menuBar = MenuBarController(actions: .init(
            openCompanion: { [weak self] in
                guard let self else { return }
                if companion.isFrontmost {
                    companion.close()
                } else {
                    companion.show()
                    // Opening reasserts the mode, or a window restored at one
                    // size shows the layout for another.
                    companion.apply(mode: self.model.displayMode)
                }
            },
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
            setKeyboardSize: { [weak self] size in self?.bridge?.setKeyboardSize(size) },
            setNaming: { [weak self] naming in self?.model.naming = naming },
            toggleRoleColors: { [weak self] in self?.model.roleColors.toggle() }
        ))
        menuBar.currentSourceIsAudio = { [weak self] in self?.bridge?.session.source == .audio }
        menuBar.currentAlwaysOnTop = { companion.isAlwaysOnTop }
        menuBar.currentPassthrough = { [weak self] in self?.bridge?.session.midiOut.passthrough ?? false }
        menuBar.currentDisplayMode = { [weak self] in self?.model.displayMode ?? .companion }
        menuBar.currentLockedKey = { [weak self] in self?.model.lockedKey }
        menuBar.currentPerformanceCount = { [weak self] in self?.bridge?.session.recorder.count ?? 0 }
        menuBar.currentKeyboardSize = { [weak self] in self?.bridge?.keyboardSize ?? .default }
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
        let hotKey = GlobalHotKey { [weak self] in
            guard let self else { return }
            if companion.isFrontmost {
                companion.close()
            } else {
                companion.show()
                companion.apply(mode: self.model.displayMode)
            }
        }
        hotKey.register(keyCode: UInt32(kVK_ANSI_C),
                        modifiers: UInt32(cmdKey | optionKey | controlKey))
        companionHotKey = hotKey

        // Toggles between the two window sizes without going near the menu
        // bar, which on a notched MacBook can be full.
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

        // The window is the app. It used to be optional because there was an
        // island above the menu bar showing the chord; with that gone, starting
        // hidden means launching Chordware puts nothing on screen at all.
        // `--hidden` is for launching it ahead of a session without the window
        // taking over the display.
        if !arguments.contains("--hidden") {
            companion.show()
            companion.apply(mode: model.displayMode)
        }

        // `--demo` replays a scripted progression, which is how the island is
        // tuned and screenshotted. Everything else runs on live input.
        if arguments.contains("--demo") {
            let driver = DemoDriver(model: model)
            driver.start(stepping: arguments.contains("--step"))
            demo = driver
        } else if !arguments.contains("--no-input") {
            let bridge = SessionBridge(model: model)
            if arguments.contains("--audio") { bridge.session.source = .audio }
            if let index = arguments.firstIndex(of: "--audio-device"), index + 1 < arguments.count {
                bridge.session.source = .audio
                bridge.session.startAudio(deviceID: arguments[index + 1])
            }
            bridge.start()
            self.bridge = bridge
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
    }
}
