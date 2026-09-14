import ChordwareCore
import ChordwareEngine
import ChordwareIsland
import Foundation

/// Connects the live input pipeline to what the window renders.
///
/// The engine knows nothing about the view and the view knows nothing about
/// CoreMIDI; this is the only place the two meet, which keeps the window
/// renderable from fixtures and the engine testable without one.
@MainActor
final class SessionBridge {
    let session = LiveSession()
    private let model: IslandModel
    private let keyboardRange = KeyboardRange()

    init(model: IslandModel) {
        self.model = model
        session.onUpdate = { [weak self] update in self?.apply(update) }
        session.onError = { [weak self] error in self?.report(error) }
        session.midiIn.onEndpointsChanged = { [weak self] _ in self?.refreshInputLabel() }
        session.midiIn.onActiveEndpointChanged = { [weak self] _ in self?.refreshInputLabel() }
    }

    func start() {
        session.start()
        refreshInputLabel()
    }

    func stop() { session.stop() }

    private func refreshInputLabel() {
        switch session.source {
        case .midi:
            let active = session.midiIn.activeEndpoints
            // Name whatever last actually sent a note. Falling back to the
            // first connected port labels the app "Logic Pro Virtual Out" when
            // the keyboard is unplugged, which tells the player nothing.
            if let playing = session.midiIn.lastActiveEndpoint {
                model.inputLabel = playing.name
            } else if let hardware = active.first(where: { !$0.isVirtual }) {
                model.inputLabel = hardware.name
            } else if active.isEmpty {
                model.inputLabel = "no MIDI device connected"
            } else {
                model.inputLabel = "waiting for MIDI\u{2026}"
            }
        case .audio:
            model.inputLabel = session.audioIn.currentDevice?.name ?? "no audio input"
        }
    }

    private func applyRange() {
        model.keyboardSize = keyboardRange.size
    }

    func setKeyboardSize(_ size: KeyboardSize) {
        guard keyboardRange.set(size) else { return }
        applyRange()
    }

    var keyboardSize: KeyboardSize { keyboardRange.size }

    private func apply(_ update: LiveSession.Update) {
        model.chroma = update.chroma
        model.sustainDown = update.sustainDown
        model.velocities = update.velocities


        guard !update.candidates.isEmpty else {
            // No chord does not mean no music. One key held is a note and two
            // are an interval; both should stay on screen and lit.
            if update.notes.isEmpty {
                model.clearNotes(atMs: update.timeMs)
            } else {
                model.key = update.key
                model.presentNotesOnly(update.notes, atMs: update.timeMs)
            }
            return
        }

        model.key = update.key
        model.keyConfidence = update.keyConfidence
        model.present(candidates: update.candidates,
                      heldNotes: update.notes,
                      atMs: update.timeMs,
                      settled: update.isSettled)
    }

    /// Say so in the one place that is always visible, rather than in a
    /// notification that decays before you look up from the keys.
    private func report(_ error: Error) {
        model.inputLabel = "input problem: \(error)"
    }
}
