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
        /// True once the notes have stopped moving and this really is the chord
        /// that was played, rather than the two notes that happened to land
        /// first. Only settled chords belong in the progression or the key.
        public let isSettled: Bool
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
    /// The notes that produced the chord on screen, so a shrinking set can be
    /// told apart from a new one.
    private var chordAnchor: Set<Int> = []
    /// Bumped on every change, so a pending settle knows it is stale.
    private var settleGeneration = 0
    private var hasPendingSettle = false
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

    /// Feed in a MIDI message as though it had arrived from hardware.
    ///
    /// Hardware calls this through `midiIn`; the self-test calls it directly,
    /// which is the only way to play a phrase without a keyboard attached.
    public func ingest(_ message: MIDIMessage) { handle(message) }

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
        // Taking a chord off the keys uncovers fragments of it, and analysing
        // those fragments names chords nobody played: lift the D from a D minor
        // triad and the F and A left behind read as F major. The fragment that
        // happens to come off last is then what stays on screen, so the display
        // ends up showing the *previous* chord's debris -- which looks, from the
        // keys, exactly like a chord that failed to register.
        //
        // A shrinking set that is still part of the chord in hand is a release,
        // not a new voicing. Keep the chord and only update which keys are lit.
        // Three notes or more can stand on their own, so dropping the 7th from a
        // Cmaj7 still re-reads as C.
        if !notes.isEmpty, notes.count < 3,
           !chordAnchor.isEmpty, chordAnchor.isSuperset(of: notes) {
            publish(notes: notes)
            return
        }
        guard notes.count >= 2 else {
            // A chord let go before it had time to settle is still a chord that
            // was played, so record it on the way out rather than losing it.
            if hasPendingSettle { settle() }
            candidates = []
            chordAnchor = []
            cancelSettle()
            publish(notes: notes)
            return
        }
        let options = ChordDetector.Options(key: effectiveKey, maxCandidates: 5)
        candidates = ChordDetector.detect(midiNotes: notes, options: options)
        chordAnchor = Set(notes)
        publish(notes: notes)
        scheduleSettle()
    }

    /// Show every reading immediately, but only *believe* the settled one.
    ///
    /// Fingers do not land together. Playing D minor, the F and the A arrive
    /// first and read as F major; playing G, the B and the D read as B minor.
    /// Showing those is honest -- the chord really is forming -- but recording
    /// them as chords that were played, and letting them vote on the key, is
    /// not. It fills the progression strip with chords nobody played and drags
    /// the key estimate around behind them.
    private func scheduleSettle() {
        settleGeneration &+= 1
        hasPendingSettle = true
        let generation = settleGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
            guard let self, self.settleGeneration == generation else { return }
            self.settle()
        }
    }

    /// Long enough for a hand to finish arriving, short enough to be invisible.
    private static let settleDelay: TimeInterval = 0.14

    private func settle() {
        hasPendingSettle = false
        guard let chord = candidates.first?.chord else { return }
        keyEstimator.observe(chord: chord, at: Date().timeIntervalSince(started))
        updateKey()
        publish(notes: source == .midi ? held.sounding : audioNotes, settled: true)
    }

    /// Stop a pending settle, for when the chord is being torn down rather than
    /// changed.
    private func cancelSettle() {
        settleGeneration &+= 1
        hasPendingSettle = false
    }

    // MARK: - Audio

    private func switchSource() {
        held.allNotesOff()
        candidates = []
        chordAnchor = []
        cancelSettle()
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

    private func publish(notes: [Int], settled: Bool = false) {
        onUpdate?(Update(
            candidates: candidates,
            notes: notes,
            key: effectiveKey,
            keyConfidence: lockedKey != nil ? 1 : keyConfidence,
            chroma: source == .audio ? lastChroma : nil,
            velocities: held.velocities,
            sustainDown: held.sustainDown,
            timeMs: nowMs,
            isSettled: settled
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
        chordAnchor = []
        cancelSettle()
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
