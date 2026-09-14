import AppKit
import ChordwareCore
import ChordwareUI

/// Feeds the window a scripted progression so the UI can be built and verified
/// without a keyboard plugged in. Kept behind `--demo` for screenshots and
/// tuning.
@MainActor
final class DemoDriver {
    private let model: AppModel
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

    init(model: AppModel) {
        self.model = model
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
        if let estimate = model.progression.estimatedKey {
            model.key = estimate.key
        }
    }
}
