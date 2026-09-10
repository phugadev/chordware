import AppKit

/// A status-bar item, so a background app with no Dock icon is still reachable.
///
/// Without this there is no way to open the window, switch input, or even quit
/// Chordware short of killing the process.
@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    public struct Actions {
        public var openCompanion: () -> Void
        public var toggleAlwaysOnTop: () -> Void
        public var chooseMIDI: () -> Void
        public var chooseAudio: () -> Void
        public var togglePassthrough: () -> Void
        public var resetProgression: () -> Void

        public init(openCompanion: @escaping () -> Void,
                    toggleAlwaysOnTop: @escaping () -> Void,
                    chooseMIDI: @escaping () -> Void,
                    chooseAudio: @escaping () -> Void,
                    togglePassthrough: @escaping () -> Void,
                    resetProgression: @escaping () -> Void) {
            self.openCompanion = openCompanion
            self.toggleAlwaysOnTop = toggleAlwaysOnTop
            self.chooseMIDI = chooseMIDI
            self.chooseAudio = chooseAudio
            self.togglePassthrough = togglePassthrough
            self.resetProgression = resetProgression
        }
    }

    /// Queried when the menu opens, so the state shown is current.
    public var currentSourceIsAudio: () -> Bool = { false }
    public var currentAlwaysOnTop: () -> Bool = { false }
    public var currentChordSummary: () -> String? = { nil }
    public var currentPassthrough: () -> Bool = { false }

    private var statusItem: NSStatusItem?
    private let actions: Actions

    public init(actions: Actions) {
        self.actions = actions
        super.init()
    }

    public func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "pianokeys",
                                     accessibilityDescription: "Chordware")
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        rebuild(menu)
    }

    public func menuWillOpen(_ menu: NSMenu) { rebuild(menu) }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        if let summary = currentChordSummary() {
            let item = NSMenuItem(title: summary, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let window = NSMenuItem(title: "Companion Window", action: #selector(fire(_:)),
                                keyEquivalent: "c")
        window.keyEquivalentModifierMask = [.command, .option, .control]
        window.target = self
        window.representedObject = Box { [weak self] in self?.actions.openCompanion() }
        menu.addItem(window)
        add(menu, "Keep Window on Top", key: "t", checked: currentAlwaysOnTop()) { [weak self] in
            self?.actions.toggleAlwaysOnTop()
        }
        menu.addItem(.separator())

        let audio = currentSourceIsAudio()
        add(menu, "Listen to MIDI", key: "", checked: !audio) { [weak self] in
            self?.actions.chooseMIDI()
        }
        add(menu, "Listen to Audio", key: "", checked: audio) { [weak self] in
            self?.actions.chooseAudio()
        }

        let passthrough = NSMenuItem(title: "Send MIDI to DAW (passthrough)",
                                     action: #selector(fire(_:)), keyEquivalent: "")
        passthrough.target = self
        passthrough.representedObject = Box { [weak self] in self?.actions.togglePassthrough() }
        passthrough.state = currentPassthrough() ? .on : .off
        // Doubled notes are the classic symptom of turning this on without
        // also telling the DAW to stop listening to the keyboard directly.
        passthrough.toolTip = "Only turn this on if your DAW listens to Chordware "
            + "instead of your keyboard, or you will hear every note twice."
        menu.addItem(passthrough)
        menu.addItem(.separator())

        add(menu, "Clear Progression", key: "k") { [weak self] in self?.actions.resetProgression() }
        menu.addItem(.separator())
        add(menu, "Quit Chordware", key: "q") { NSApp.terminate(nil) }
    }

    private func add(_ menu: NSMenu, _ title: String, key: String,
                     checked: Bool = false, handler: @escaping () -> Void) {
        let item = NSMenuItem(title: title, action: #selector(fire(_:)), keyEquivalent: key)
        item.target = self
        item.representedObject = Box(handler)
        item.state = checked ? .on : .off
        menu.addItem(item)
    }

    private final class Box {
        let handler: () -> Void
        init(_ handler: @escaping () -> Void) { self.handler = handler }
    }

    @objc private func fire(_ sender: NSMenuItem) {
        (sender.representedObject as? Box)?.handler()
    }
}
