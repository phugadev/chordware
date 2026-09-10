import ChordwareCore
import ChordwareEngine
import ChordwareIsland
import Foundation

/// Connects the live input pipeline to what the island renders.
///
/// The engine knows nothing about the island and the island knows nothing about
/// CoreMIDI; this is the only place the two meet, which keeps the island
/// renderable from fixtures and the engine testable without a window.
@MainActor
final class SessionBridge {
    let session = LiveSession()
    private let model: IslandModel
    private let controller: IslandController
    private var lastKey: Key?
    private var lastCadenceIndex: Int?

    init(model: IslandModel, controller: IslandController) {
        self.model = model
        self.controller = controller
        session.onUpdate = { [weak self] update in self?.apply(update) }
        session.onError = { [weak self] error in self?.report(error) }
        session.midiIn.onEndpointsChanged = { [weak self] _ in self?.refreshInputLabel() }
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
            model.inputLabel = active.first?.name ?? "no MIDI input"
        case .audio:
            model.inputLabel = session.audioIn.currentDevice?.name ?? "no audio input"
        }
    }

    private func apply(_ update: LiveSession.Update) {
        model.chroma = update.chroma

        guard !update.candidates.isEmpty else {
            model.clearNotes(atMs: update.timeMs)
            return
        }

        model.key = update.key
        model.keyConfidence = update.keyConfidence
        model.present(candidates: update.candidates,
                      heldNotes: update.notes,
                      atMs: update.timeMs)

        announce(update)
    }

    /// Surface the things worth interrupting for: a key change, and a cadence
    /// as it lands.
    private func announce(_ update: LiveSession.Update) {
        if let key = update.key, key != lastKey {
            if lastKey != nil, update.keyConfidence > 0.65 {
                controller.toast(IslandToast(kind: .key, title: key.name, detail: "key change"))
            }
            lastKey = key
        }

        guard let key = update.key else { return }
        let cadences = model.progression.cadences(in: key)
        guard let last = cadences.last,
              last.index == model.progression.count - 1,
              last.index != lastCadenceIndex else { return }
        lastCadenceIndex = last.index
        controller.toast(IslandToast(kind: .cadence,
                                     title: last.cadence.display,
                                     detail: model.chord?.symbol()))
    }

    private func report(_ error: Error) {
        controller.toast(IslandToast(kind: .capture,
                                     title: "input problem",
                                     detail: "\(error)"),
                         duration: 4)
    }
}
