import AppKit
import ChordwareCore
import ChordwareIsland

/// Feeds the island a scripted progression so the UI can be built and verified
/// before any MIDI or audio input exists. Deleted from the shipping path once
/// the engines land; kept behind `--demo` for screenshots and tuning.
@MainActor
final class DemoDriver {
    private let model: IslandModel
    private let controller: IslandController
    private var task: Task<Void, Never>?
    private var stepMonitor: Any?
    private var index = 0

    /// A progression that exercises the analysis: a secondary dominant, a
    /// borrowed chord, and a backdoor cadence.
    private let script: [(voicing: String, hold: Double)] = [
        ("C3 E4 G4 B4", 2.0),
        ("A2 E4 G4 C#5", 2.0),
        ("D3 F4 A4 C5", 2.0),
        ("G2 F4 B4 D5", 2.0),
        ("C3 E4 G4 B4 D5", 2.4),
        ("Ab2 Eb4 Ab4 C5", 2.0),
        ("Bb2 Ab4 D5 F5", 2.0),
        ("C3 E4 G4 B4 D5 A5", 3.0),
    ]

    init(model: IslandModel, controller: IslandController) {
        self.model = model
        self.controller = controller
        model.inputLabel = "demo"
    }

    func start(stepping: Bool) {
        if stepping {
            // Space advances one chord, for taking screenshots of exact states.
            stepMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard event.keyCode == 49 else { return }
                Task { @MainActor in self?.advance() }
            }
            advance()
            return
        }
        task = Task { @MainActor in
            while !Task.isCancelled {
                let hold = script[index % script.count].hold
                advance()
                try? await Task.sleep(for: .seconds(hold))
            }
        }
    }

    func stop() {
        task?.cancel()
        if let stepMonitor { NSEvent.removeMonitor(stepMonitor) }
    }

    private func advance() {
        let entry = script[index % script.count]
        index += 1
        guard let notes = MIDINote.parseList(entry.voicing) else { return }

        let options = ChordDetector.Options(key: model.key, maxCandidates: 5)
        let candidates = ChordDetector.detect(midiNotes: notes, options: options)
        let time = index * 2000
        model.present(candidates: candidates, heldNotes: notes, atMs: time)

        // Re-estimate the key from what has been captured so far.
        let previousKey = model.key
        if let estimate = model.progression.estimatedKey {
            model.key = estimate.key
            model.keyConfidence = estimate.confidence
            if let previousKey, previousKey != estimate.key, estimate.confidence > 0.6 {
                controller.toast(IslandToast(kind: .key, title: estimate.key.name,
                                             detail: "key change"))
            }
        }

        if let key = model.key {
            let cadences = model.progression.cadences(in: key)
            if let last = cadences.last, last.index == model.progression.count - 1 {
                controller.toast(IslandToast(kind: .cadence, title: last.cadence.display,
                                             detail: model.chord?.symbol()))
            }
        }
    }
}
