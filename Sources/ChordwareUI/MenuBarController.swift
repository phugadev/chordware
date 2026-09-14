import AppKit
import ChordwareCore

/// A status-bar item, so a background app with no Dock icon is still reachable.
///
/// Deliberately short. This menu used to carry a display mode, a key you could
/// lock, three note-naming systems, a role-colour toggle and a choice of audio
/// input, for a window that has none of those things on it.
@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    public struct Actions {
        public var toggleWindow: () -> Void
        public var toggleAlwaysOnTop: () -> Void
        public var exportPerformance: () -> Void
        public var togglePassthrough: () -> Void
        public var panic: () -> Void
        public var clearHistory: () -> Void
        public var setKeyboardSize: (KeyboardSize) -> Void

        public init(toggleWindow: @escaping () -> Void,
                    toggleAlwaysOnTop: @escaping () -> Void,
                    exportPerformance: @escaping () -> Void,
                    togglePassthrough: @escaping () -> Void,
                    panic: @escaping () -> Void,
                    clearHistory: @escaping () -> Void,
                    setKeyboardSize: @escaping (KeyboardSize) -> Void) {
            self.toggleWindow = toggleWindow
            self.toggleAlwaysOnTop = toggleAlwaysOnTop
            self.exportPerformance = exportPerformance
            self.togglePassthrough = togglePassthrough
            self.panic = panic
            self.clearHistory = clearHistory
            self.setKeyboardSize = setKeyboardSize
        }
    }

    /// Queried when the menu opens, so the state shown is current.
    public var currentAlwaysOnTop: () -> Bool = { false }
    public var currentChordSummary: () -> String? = { nil }
    public var currentPassthrough: () -> Bool = { false }
    /// How many notes are waiting to be exported, for the menu title.
    public var currentPerformanceCount: () -> Int = { 0 }
    /// How many chords are in the strip, so the item can say what it clears.
    public var currentHistoryCount: () -> Int = { 0 }
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
        window.representedObject = Box { [weak self] in self?.actions.toggleWindow() }
        menu.addItem(window)
        add(menu, "Keep Window on Top", key: "t", checked: currentAlwaysOnTop()) { [weak self] in
            self?.actions.toggleAlwaysOnTop()
        }
        menu.addItem(.separator())

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

        // The strip along the foot of the window grows for as long as the app
        // is running, and nothing else empties it: panic is about notes stuck
        // down, not about what you played an hour ago.
        let chords = currentHistoryCount()
        let clear = NSMenuItem(
            title: chords > 0 ? "Clear History (\(chords) chords)" : "Clear History",
            action: #selector(fire(_:)), keyEquivalent: "k")
        clear.target = self
        clear.isEnabled = chords > 0
        clear.representedObject = Box { [weak self] in self?.actions.clearHistory() }
        menu.addItem(clear)

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
