import AppKit
import ChordwareCore

/// A status-bar item, so a background app with no Dock icon is still reachable.
///
/// Deliberately short. This menu used to carry a display mode, a key you could
/// lock, three note-naming systems, a role-colour toggle and two clear
/// commands, for a window that no longer has any of those things on it.
@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    public struct Actions {
        public var openCompanion: () -> Void
        public var toggleAlwaysOnTop: () -> Void
        public var exportPerformance: () -> Void
        public var chooseMIDI: () -> Void
        public var chooseAudio: () -> Void
        public var togglePassthrough: () -> Void
        public var panic: () -> Void
        public var setKeyboardSize: (KeyboardSize) -> Void

        public init(openCompanion: @escaping () -> Void,
                    toggleAlwaysOnTop: @escaping () -> Void,
                    exportPerformance: @escaping () -> Void,
                    chooseMIDI: @escaping () -> Void,
                    chooseAudio: @escaping () -> Void,
                    togglePassthrough: @escaping () -> Void,
                    panic: @escaping () -> Void,
                    setKeyboardSize: @escaping (KeyboardSize) -> Void) {
            self.openCompanion = openCompanion
            self.toggleAlwaysOnTop = toggleAlwaysOnTop
            self.exportPerformance = exportPerformance
            self.chooseMIDI = chooseMIDI
            self.chooseAudio = chooseAudio
            self.togglePassthrough = togglePassthrough
            self.panic = panic
            self.setKeyboardSize = setKeyboardSize
        }
    }

    /// Queried when the menu opens, so the state shown is current.
    public var currentSourceIsAudio: () -> Bool = { false }
    public var currentAlwaysOnTop: () -> Bool = { false }
    public var currentChordSummary: () -> String? = { nil }
    public var currentPassthrough: () -> Bool = { false }
    /// How many notes are waiting to be exported, for the menu title.
    public var currentPerformanceCount: () -> Int = { 0 }
    public var currentKeyboardSize: () -> KeyboardSize = { .default }

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

    /// Items are enabled explicitly rather than by a responder chain, since a
    /// status-bar menu has none.
    public func menu(_ menu: NSMenu, update item: NSMenuItem,
                     at index: Int, shouldCancel: Bool) -> Bool { true }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        if let summary = currentChordSummary() {
            let item = NSMenuItem(title: summary, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let window = NSMenuItem(title: "Show Window", action: #selector(fire(_:)),
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

        let keyboard = NSMenuItem(title: "Keyboard", action: nil, keyEquivalent: "")
        let keyboardMenu = NSMenu()
        let current = currentKeyboardSize()
        for option in KeyboardSize.allCases {
            let item = NSMenuItem(title: option.displayName, action: #selector(fire(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.state = option == current ? .on : .off
            item.representedObject = Box { [weak self] in self?.actions.setKeyboardSize(option) }
            keyboardMenu.addItem(item)
        }
        keyboard.submenu = keyboardMenu
        keyboard.toolTip = "Fixed. The keyboard never resizes itself while you play."
        menu.addItem(keyboard)

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

        let captured = currentPerformanceCount()
        let export = NSMenuItem(
            title: captured > 0 ? "Save Performance as MIDI\u{2026} (\(captured) notes)"
                                : "Save Performance as MIDI\u{2026}",
            action: #selector(fire(_:)), keyEquivalent: "s")
        export.target = self
        export.isEnabled = captured > 0
        export.representedObject = Box { [weak self] in self?.actions.exportPerformance() }
        export.toolTip = "Everything played since Chordware started, as a .mid file."
        menu.addItem(export)

        let panic = NSMenuItem(title: "Panic (All Notes Off)", action: #selector(fire(_:)),
                               keyEquivalent: ".")
        panic.keyEquivalentModifierMask = [.command]
        panic.target = self
        panic.representedObject = Box { [weak self] in self?.actions.panic() }
        panic.toolTip = "Clears any key stuck lit and tells the MIDI port to release "
            + "everything. For a Note Off that never arrived, or a pedal that never came up."
        menu.addItem(panic)
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
