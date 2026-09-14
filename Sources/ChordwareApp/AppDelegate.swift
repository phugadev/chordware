import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers
import ChordwareCore
import ChordwareEngine
import ChordwareUI

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

    private let model = AppModel()
    private var bridge: SessionBridge?
    private var demo: DemoDriver?
    private var windowController: WindowController?
    private var menuBar: MenuBarController?
    /// Held, or the Carbon handlers are torn down the moment these go out of
    /// scope and the shortcuts stop working.
    private var hotKeys: [GlobalHotKey] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments

        // `--render <dir>` writes the window's layout to PNG and exits, which
        // is how it is reviewed without anything on screen.
        if let index = arguments.firstIndex(of: "--render"), index + 1 < arguments.count {
            let directory = URL(fileURLWithPath: arguments[index + 1])
            do {
                let written = try Renderer.renderAll(to: directory)
                for url in written { print(url.path) }
            } catch {
                FileHandle.standardError.write(Data("render failed: \(error)\n".utf8))
                exit(1)
            }
            exit(0)
        }

        let window = WindowController(model: model)
        self.windowController = window

        // A background app with no Dock icon needs a status item, or there is
        // no way to open the window, change input, or even quit.
        let menuBar = MenuBarController(actions: .init(
            toggleWindow: { window.isFrontmost ? window.close() : window.show() },
            toggleAlwaysOnTop: { window.setAlwaysOnTop(!window.isAlwaysOnTop) },
            exportPerformance: { [weak self] in self?.exportPerformance() },
            togglePassthrough: { [weak self] in
                guard let out = self?.bridge?.session.midiOut else { return }
                out.passthrough.toggle()
                if !out.passthrough { out.allNotesOff() }
            },
            panic: { [weak self] in
                self?.bridge?.session.panic()
                self?.model.clearChord()
            },
            clearHistory: { [weak self] in self?.model.clearHistory() },
            setKeyboardSize: { [weak self] size in self?.bridge?.setKeyboardSize(size) }
        ))
        menuBar.currentAlwaysOnTop = { window.isAlwaysOnTop }
        menuBar.currentPassthrough = { [weak self] in self?.bridge?.session.midiOut.passthrough ?? false }
        menuBar.currentPerformanceCount = { [weak self] in self?.bridge?.session.recorder.count ?? 0 }
        menuBar.currentHistoryCount = { [weak self] in self?.model.progression.count ?? 0 }
        menuBar.currentKeyboardSize = { [weak self] in self?.bridge?.keyboardSize ?? .default }
        menuBar.currentChordSummary = { [weak self] in self?.model.chord?.symbol() }
        menuBar.install()
        self.menuBar = menuBar

        // Everything the app can do, reachable without the menu bar.
        //
        // Chordware has no Dock icon, and on a MacBook with a full menu bar its
        // status item is pushed behind the notch where it cannot be clicked --
        // which leaves the app running with no way to reach it at all. These do
        // not depend on any of that being visible.
        let modifiers = UInt32(cmdKey | optionKey | controlKey)
        let shortcuts: [(Int, () -> Void)] = [
            // Show or hide the window.
            (kVK_ANSI_C, { window.isFrontmost ? window.close() : window.show() }),
            // Keep it above the DAW, or stop.
            (kVK_ANSI_T, { window.setAlwaysOnTop(!window.isAlwaysOnTop) }),
            // Panic: for a Note Off that never arrived or a pedal that never
            // came up, both of which leave keys lit with nothing sounding.
            (kVK_ANSI_K, { [weak self] in
                self?.bridge?.session.panic()
                self?.model.clearChord()
            }),
        ]
        for (code, action) in shortcuts {
            let hotKey = GlobalHotKey(action: action)
            // Registration fails silently when another app already owns the
            // combination, and a shortcut that does nothing is worse here than
            // anywhere else: it is the only way in when the status item is
            // hidden behind the notch. Say so where it can be read.
            if !hotKey.register(keyCode: UInt32(code), modifiers: modifiers) {
                FileHandle.standardError.write(Data(
                    "chordware: shortcut for key code \(code) is already taken\n".utf8))
            }
            hotKeys.append(hotKey)
        }

        // The window is the app. It used to be optional because there was an
        // island above the menu bar showing the chord; with that gone, starting
        // hidden means launching Chordware puts nothing on screen at all.
        // `--hidden` is for launching it ahead of a session without the window
        // taking over the display.
        if !arguments.contains("--hidden") {
            window.show()
        }

        // `--demo` replays a scripted progression, which is how the island is
        // tuned and screenshotted. Everything else runs on live input.
        if arguments.contains("--demo") {
            let driver = DemoDriver(model: model)
            driver.start(stepping: arguments.contains("--step"))
            demo = driver
        } else if !arguments.contains("--no-input") {
            let bridge = SessionBridge(model: model)
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
