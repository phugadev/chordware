import AppKit
import ChordwareCore

/// A status-bar item, so a background app with no Dock icon is still reachable.
///
/// Without this there is no way to open the window, switch input, or even quit
/// Chordware short of killing the process.
@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    public struct Actions {
        public var openCompanion: () -> Void
        public var toggleAlwaysOnTop: () -> Void
        public var setDisplayMode: (DisplayMode) -> Void
        public var setKey: (Key?) -> Void
        public var exportPerformance: () -> Void
        public var clearPerformance: () -> Void
        public var chooseMIDI: () -> Void
        public var chooseAudio: () -> Void
        public var togglePassthrough: () -> Void
        public var resetProgression: () -> Void
        public var panic: () -> Void
        public var resetKeyboardRange: () -> Void
        public var setNaming: (NoteNaming) -> Void
        public var toggleRoleColors: () -> Void

        public init(openCompanion: @escaping () -> Void,
                    toggleAlwaysOnTop: @escaping () -> Void,
                    setDisplayMode: @escaping (DisplayMode) -> Void,
                    setKey: @escaping (Key?) -> Void,
                    exportPerformance: @escaping () -> Void,
                    clearPerformance: @escaping () -> Void,
                    chooseMIDI: @escaping () -> Void,
                    chooseAudio: @escaping () -> Void,
                    togglePassthrough: @escaping () -> Void,
                    resetProgression: @escaping () -> Void,
                    panic: @escaping () -> Void,
                    resetKeyboardRange: @escaping () -> Void,
                    setNaming: @escaping (NoteNaming) -> Void,
                    toggleRoleColors: @escaping () -> Void) {
            self.openCompanion = openCompanion
            self.toggleAlwaysOnTop = toggleAlwaysOnTop
            self.setDisplayMode = setDisplayMode
            self.setKey = setKey
            self.exportPerformance = exportPerformance
            self.clearPerformance = clearPerformance
            self.chooseMIDI = chooseMIDI
            self.chooseAudio = chooseAudio
            self.togglePassthrough = togglePassthrough
            self.resetProgression = resetProgression
            self.panic = panic
            self.resetKeyboardRange = resetKeyboardRange
            self.setNaming = setNaming
            self.toggleRoleColors = toggleRoleColors
        }
    }

    /// Queried when the menu opens, so the state shown is current.
    public var currentSourceIsAudio: () -> Bool = { false }
    public var currentAlwaysOnTop: () -> Bool = { false }
    public var currentChordSummary: () -> String? = { nil }
    public var currentPassthrough: () -> Bool = { false }
    public var currentDisplayMode: () -> DisplayMode = { .companion }
    public var currentLockedKey: () -> Key? = { nil }
    /// How many notes are waiting to be exported, for the menu title.
    public var currentPerformanceCount: () -> Int = { 0 }
    public var currentNaming: () -> NoteNaming = { .letters }
    public var currentRoleColors: () -> Bool = { true }

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

        let window = NSMenuItem(title: "Companion Window", action: #selector(fire(_:)),
                                keyEquivalent: "c")
        window.keyEquivalentModifierMask = [.command, .option, .control]
        window.target = self
        window.representedObject = Box { [weak self] in self?.actions.openCompanion() }
        menu.addItem(window)
        add(menu, "Keep Window on Top", key: "t", checked: currentAlwaysOnTop()) { [weak self] in
            self?.actions.toggleAlwaysOnTop()
        }
        let mode = currentDisplayMode()
        for option in DisplayMode.allCases {
            let item = NSMenuItem(title: option.displayName, action: #selector(fire(_:)),
                                  keyEquivalent: option == .presentation ? "p" : "")
            if option == .presentation {
                item.keyEquivalentModifierMask = [.command, .option, .control]
            }
            item.target = self
            item.state = option == mode ? .on : .off
            item.representedObject = Box { [weak self] in self?.actions.setDisplayMode(option) }
            switch option {
            case .companion: item.toolTip = "Everything: notes, alternatives, scales, progression."
            case .presentation: item.toolTip = "Just the chord and the keyboard, in a window that fits it."
            }
            menu.addItem(item)
        }
        add(menu, "Colour Keys by Role", key: "", checked: currentRoleColors()) { [weak self] in
            self?.actions.toggleRoleColors()
        }

        // Spelling depends on the key, and the key takes a few chords to
        // establish. Naming it up front is the answer to "why is my D minor
        // full of sharps".
        let keyItem = NSMenuItem(title: "Key", action: nil, keyEquivalent: "")
        let keyMenu = NSMenu()
        let locked = currentLockedKey()
        let auto = NSMenuItem(title: "Detect Automatically", action: #selector(fire(_:)),
                              keyEquivalent: "")
        auto.target = self
        auto.state = locked == nil ? .on : .off
        auto.representedObject = Box { [weak self] in self?.actions.setKey(nil) }
        keyMenu.addItem(auto)
        keyMenu.addItem(.separator())
        for candidate in Key.allKeys {
            let item = NSMenuItem(title: candidate.name, action: #selector(fire(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.state = candidate == locked ? .on : .off
            item.representedObject = Box { [weak self] in self?.actions.setKey(candidate) }
            keyMenu.addItem(item)
        }
        keyItem.submenu = keyMenu
        menu.addItem(keyItem)

        let namingItem = NSMenuItem(title: "Note Names", action: nil, keyEquivalent: "")
        let namingMenu = NSMenu()
        let naming = currentNaming()
        for option in NoteNaming.allCases {
            let item = NSMenuItem(title: option.displayName, action: #selector(fire(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.state = option == naming ? .on : .off
            item.representedObject = Box { [weak self] in self?.actions.setNaming(option) }
            if option.requiresKey {
                item.toolTip = "Relative to the detected key, so it needs one to be established."
            }
            namingMenu.addItem(item)
        }
        namingItem.submenu = namingMenu
        menu.addItem(namingItem)
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
        add(menu, "Clear Performance", key: "") { [weak self] in self?.actions.clearPerformance() }
        menu.addItem(.separator())

        add(menu, "Clear Progression", key: "k") { [weak self] in self?.actions.resetProgression() }
        add(menu, "Refit Keyboard to Controller", key: "") { [weak self] in
            self?.actions.resetKeyboardRange()
        }
        let panic = NSMenuItem(title: "Panic (All Notes Off)", action: #selector(fire(_:)), keyEquivalent: ".")
        panic.keyEquivalentModifierMask = [.command]
        panic.target = self
        panic.representedObject = Box { [weak self] in self?.actions.panic() }
        panic.toolTip = "Clears any key stuck lit and tells the MIDI port to release everything. For a Note Off that never arrived, or a pedal that never came up."
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
