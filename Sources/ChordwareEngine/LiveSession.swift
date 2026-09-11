import ChordwareCore
import ChordwareSignal
import Foundation

/// The single place notes become harmony.
///
/// MIDI and audio arrive by different routes but converge here, so the island,
/// the progression recorder and (later) the HTTP API all consume one stream
/// rather than each re-deriving chords from raw input.
@MainActor
public final class LiveSession {
    public enum InputSource: String, CaseIterable, Sendable {
        case midi, audio
    }

    public struct Update: Sendable {
        public let candidates: [ChordCandidate]
        /// Notes to light up: keys held, or the voices heard in the audio.
        public let notes: [Int]
        public let key: Key?
        public let keyConfidence: Double
        public let chroma: [Double]?
        /// How hard each held key was struck, for showing dynamics.
        public let velocities: [Int: Int]
        public let sustainDown: Bool
        public let timeMs: Int
    }

    public var source: InputSource = .midi {
        didSet { if source != oldValue { switchSource() } }
    }

    public private(set) var held = HeldNotes()
    public private(set) var candidates: [ChordCandidate] = []
    public private(set) var key: Key?
    public private(set) var keyConfidence: Double = 0
    /// When set, overrides the estimate everywhere.
    /// Naming a key re-runs detection rather than just re-publishing.
    ///
    /// Re-publishing hands back the candidates found under the *previous* key,
    /// so the chord keeps its old spelling and its old Roman numeral and
    /// locking appears to do nothing at all until the next note is played.
    public var lockedKey: Key? { didSet { reanalyse() } }

    public let midiIn = MIDIInputEngine()
    public let midiOut = MIDIOutputEngine()
    public let audioIn = AudioInputEngine()
    public let synth = PreviewSynth()
    /// Always capturing, so a good idea found by accident is not lost.
    public let recorder = PerformanceRecorder()

    public var onUpdate: ((Update) -> Void)?
    public var onError: ((Error) -> Void)?

    private let keyEstimator = KeyEstimator(halfLife: 14, minimumObservations: 4)
    private var extractor: ChromaExtractor?
    private let tracker = AudioChordTracker()
    private var extractorSampleRate: Double = 0
    private var lastChroma: [Double]?
    private var audioNotes: [Int] = []
    private let started = Date()

    public init() {
        midiIn.onMessage = { [weak self] message in self?.handle(message) }
    }

    private var nowMs: Int { Int(Date().timeIntervalSince(started) * 1000) }

    public func start() {
        do {
            // Output first: the input engine needs the virtual source's ID so
            // it can refuse to listen to our own passthrough.
            try midiOut.start()
            if let uid = midiOut.virtualSourceUID { midiIn.excluded = [uid] }
            try midiIn.start()
        } catch {
            onError?(error)
        }
        if source == .audio { startAudio() }
    }

    public func stop() {
        midiIn.stop()
        midiOut.stop()
        audioIn.stop()
        synth.stop()
    }

    // MARK: - MIDI

    private func handle(_ message: MIDIMessage) {
        // Passthrough first, so the DAW's timing does not wait on analysis.
        midiOut.forward(message)

        let now = Date().timeIntervalSince(started)
        var changed = false
        switch message {
        case .noteOn(let note, let velocity, let channel):
            recorder.noteOn(note, velocity: velocity, channel: channel, at: now)
            changed = held.noteOn(note, velocity: velocity)
        case .noteOff(let note, let channel):
            recorder.noteOff(note, channel: channel, at: now)
            changed = held.noteOff(note)
        case .sustain(let down, _):
            changed = held.setSustain(down)
        case .allNotesOff:
            recorder.closeOpenNotes(at: now)
            changed = held.allNotesOff()
        }
        guard changed, source == .midi else { return }
        analyseHeldNotes()
    }

    private func analyseHeldNotes() {
        let notes = held.sounding
        guard notes.count >= 2 else {
            candidates = []
            publish(notes: notes)
            return
        }
        let options = ChordDetector.Options(key: effectiveKey, maxCandidates: 5)
        candidates = ChordDetector.detect(midiNotes: notes, options: options)
        if let chord = candidates.first?.chord {
            keyEstimator.observe(chord: chord, at: Date().timeIntervalSince(started))
            updateKey()
        }
        publish(notes: notes)
    }

    // MARK: - Audio

    private func switchSource() {
        held.allNotesOff()
        candidates = []
        audioNotes = []
        lastChroma = nil
        tracker.reset()
        switch source {
        case .midi: audioIn.stop()
        case .audio: startAudio()
        }
        publish(notes: [])
    }

    public func startAudio(deviceID: String? = nil) {
        audioIn.onSamples = { [weak self] samples, rate in
            self?.consume(samples: samples, sampleRate: rate)
        }
        Task { @MainActor in
            guard await AudioInputEngine.requestPermission() else {
                onError?(AudioEngineError.permissionDenied)
                return
            }
            do {
                try audioIn.start(deviceID: deviceID)
            } catch {
                onError?(error)
            }
        }
    }

    private func consume(samples: [Float], sampleRate: Double) {
        guard source == .audio else { return }
        if extractor == nil || extractorSampleRate != sampleRate {
            extractor = ChromaExtractor(configuration: .init(sampleRate: sampleRate))
            extractorSampleRate = sampleRate
            tracker.reset()
        }
        guard let extractor else { return }

        for frame in extractor.process(samples: samples) {
            lastChroma = frame.values
            audioNotes = frame.notes.sorted()
            let previous = tracker.chord
            tracker.observe(frame)
            guard tracker.chord != previous else { continue }

            if let chord = tracker.chord {
                candidates = tracker.rank(frame, limit: 5).map {
                    ChordCandidate(chord: $0.chord, confidence: min(1, $0.score),
                                   score: $0.score, missing: [], extras: [])
                }
                keyEstimator.observe(chord: chord, at: Date().timeIntervalSince(started))
                updateKey()
            } else {
                candidates = []
            }
            publish(notes: audioNotes)
        }
    }

    // MARK: - Key

    public var effectiveKey: Key? { lockedKey ?? key }

    private func updateKey() {
        guard lockedKey == nil, let estimate = keyEstimator.estimate else { return }
        key = estimate.key
        keyConfidence = estimate.confidence
        tracker.key = estimate.key
    }

    private func republish() {
        publish(notes: source == .midi ? held.sounding : audioNotes)
    }

    /// Detect again with the current key context, then publish.
    private func reanalyse() {
        switch source {
        case .midi:
            analyseHeldNotes()
        case .audio:
            let notes = audioNotes
            if !notes.isEmpty {
                candidates = ChordDetector.detect(
                    midiNotes: notes,
                    options: ChordDetector.Options(key: effectiveKey, maxCandidates: 5))
            }
            republish()
        }
    }

    private func publish(notes: [Int]) {
        onUpdate?(Update(
            candidates: candidates,
            notes: notes,
            key: effectiveKey,
            keyConfidence: lockedKey != nil ? 1 : keyConfidence,
            chroma: source == .audio ? lastChroma : nil,
            velocities: held.velocities,
            sustainDown: held.sustainDown,
            timeMs: nowMs
        ))
    }

    /// A Standard MIDI File of everything played so far.
    public func performanceData() -> Data? {
        recorder.closeOpenNotes(at: Date().timeIntervalSince(started))
        guard !recorder.isEmpty else { return nil }
        return recorder.makeFile()
    }

    /// Release everything, everywhere. The standard escape hatch for a stuck
    /// note or a pedal that never came up.
    public func panic() {
        held.setSustain(false)
        held.allNotesOff()
        candidates = []
        tracker.reset()
        midiOut.allNotesOff()
        synth.allNotesOff()
        publish(notes: [])
    }

    /// Send a chord to the DAW through the virtual port, and audition it locally.
    public func sendChord(notes: [Int], velocity: Int = 90, audition: Bool = true) {
        midiOut.playChord(notes: notes, velocity: velocity)
        if audition { synth.audition(notes: notes) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            self?.midiOut.releaseChord(notes: notes)
        }
    }
}
