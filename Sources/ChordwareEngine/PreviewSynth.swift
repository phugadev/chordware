import AVFoundation
import ChordwareCore
import Foundation
import os

/// A small additive synth for auditioning chords and scales.
///
/// Built on AVAudioSourceNode rather than AVAudioUnitSampler so the app ships
/// no soundfont: a few decaying partials with an envelope is enough to hear
/// whether a voicing works, and it keeps the bundle tiny.
public final class PreviewSynth: @unchecked Sendable {
    private struct Voice {
        var note: Int = 0
        var phase: Double = 0
        var increment: Double = 0
        var envelope: Double = 0
        var releasing = false
        var active = false
    }

    private static let maxVoices = 24
    /// Relative levels of the first few partials, which is most of the timbre.
    private static let partials: [Double] = [1.0, 0.42, 0.22, 0.11, 0.05]

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var voices = [Voice](repeating: Voice(), count: PreviewSynth.maxVoices)
    private var lock = os_unfair_lock()
    private var sampleRate: Double = 44100

    public var volume: Double = 0.22
    public private(set) var isRunning = false

    public init() {}

    public func start() {
        guard !isRunning else { return }
        let output = engine.outputNode
        let outputFormat = output.inputFormat(forBus: 0)
        sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 44100

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList in
            guard let self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            self.render(frames: Int(frameCount), into: buffers)
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: output, format: format)
        sourceNode = node

        do {
            try engine.start()
            isRunning = true
        } catch {
            engine.detach(node)
            sourceNode = nil
        }
    }

    public func stop() {
        guard isRunning else { return }
        allNotesOff()
        if let sourceNode { engine.detach(sourceNode) }
        sourceNode = nil
        engine.stop()
        isRunning = false
    }

    public func play(notes: [Int], velocity: Int = 90) {
        start()
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        for note in notes {
            guard let slot = voices.firstIndex(where: { !$0.active })
                ?? voices.firstIndex(where: { $0.releasing }) else { break }
            voices[slot] = Voice(
                note: note,
                phase: 0,
                increment: 2.0 * .pi * MIDINote.frequency(note) / sampleRate,
                envelope: 0,
                releasing: false,
                active: true
            )
        }
    }

    public func release(notes: [Int]) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        for index in voices.indices where voices[index].active && notes.contains(voices[index].note) {
            voices[index].releasing = true
        }
    }

    public func allNotesOff() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        for index in voices.indices { voices[index].releasing = true }
    }

    /// Play a chord for a fixed time, for hover-to-audition.
    public func audition(notes: [Int], seconds: Double = 1.1) {
        play(notes: notes)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.release(notes: notes)
        }
    }

    private func render(frames: Int, into buffers: UnsafeMutableAudioBufferListPointer) {
        // Runs on the audio thread. The lock is held only long enough to copy
        // voice state; nothing here allocates.
        os_unfair_lock_lock(&lock)
        let attack = 1.0 - exp(-1.0 / (0.008 * sampleRate))
        let release = 1.0 - exp(-1.0 / (0.28 * sampleRate))

        for frame in 0..<frames {
            var sample = 0.0
            for index in voices.indices where voices[index].active {
                var voice = voices[index]
                voice.envelope += voice.releasing
                    ? (0 - voice.envelope) * release
                    : (1 - voice.envelope) * attack
                if voice.releasing && voice.envelope < 0.0008 {
                    voice.active = false
                    voice.envelope = 0
                }
                var value = 0.0
                for (harmonic, level) in Self.partials.enumerated() {
                    value += level * sin(voice.phase * Double(harmonic + 1))
                }
                sample += value * voice.envelope
                voice.phase += voice.increment
                if voice.phase > 2.0 * .pi { voice.phase -= 2.0 * .pi }
                voices[index] = voice
            }
            // Soft clip so a dense voicing cannot blast the output.
            let out = Float(tanh(sample * volume))
            for buffer in buffers {
                let data = buffer.mData!.assumingMemoryBound(to: Float.self)
                data[frame] = out
            }
        }
        os_unfair_lock_unlock(&lock)
    }
}
