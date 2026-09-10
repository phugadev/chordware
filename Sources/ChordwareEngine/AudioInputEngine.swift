import AVFoundation
import ChordwareCore
import CoreAudio
import Foundation

public struct AudioDevice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let deviceID: AudioDeviceID
    public let channels: Int
    /// Loopback and virtual devices carry system audio rather than a room.
    public var isLoopback: Bool {
        let lowered = name.lowercased()
        return ["blackhole", "loopback", "soundflower", "virtual", "aggregate"]
            .contains { lowered.contains($0) }
    }
}

/// Captures audio from a chosen input and hands mono samples to the analyser.
///
/// Any input works, which is the point: a microphone for an acoustic
/// instrument, or a loopback device such as BlackHole to read chords out of
/// whatever the Mac is playing — a Logic bounce, a DJ deck, a video.
@MainActor
public final class AudioInputEngine {
    public private(set) var isRunning = false
    public private(set) var devices: [AudioDevice] = []
    public private(set) var currentDevice: AudioDevice?
    /// Mono samples plus the rate they were captured at.
    public var onSamples: (([Float], Double) -> Void)?
    /// Peak level of the last buffer, 0...1, for a meter.
    public private(set) var level: Float = 0

    private let engine = AVAudioEngine()
    private var tapInstalled = false

    public init() { refreshDevices() }

    public func refreshDevices() {
        devices = Self.inputDevices()
    }

    public static func permissionStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    /// macOS gates every audio input behind the microphone permission,
    /// including virtual loopback devices.
    public static func requestPermission() async -> Bool {
        switch permissionStatus() {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    public func start(deviceID uid: String?) throws {
        stop()
        refreshDevices()

        let device = uid.flatMap { id in devices.first { $0.id == id } }
            ?? devices.first { $0.isLoopback }
            ?? devices.first
        guard let device else { throw AudioEngineError.noInputDevice }

        // The input device is a property of the engine's underlying audio unit
        // and can only be set while the engine is stopped.
        if let unit = engine.inputNode.audioUnit {
            var target = device.deviceID
            let status = AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                &target, UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            guard status == noErr else { throw AudioEngineError.deviceSelectionFailed(status) }
        }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioEngineError.invalidFormat
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            var mono = [Float](repeating: 0, count: frames)
            // Sum to mono: harmony is the same in both channels, and stereo
            // doubles the work for nothing.
            for channel in 0..<channelCount {
                let data = channels[channel]
                for frame in 0..<frames { mono[frame] += data[frame] }
            }
            if channelCount > 1 {
                let scale = 1.0 / Float(channelCount)
                for frame in 0..<frames { mono[frame] *= scale }
            }
            let peak = mono.reduce(Float(0)) { max($0, abs($1)) }
            let rate = buffer.format.sampleRate
            Task { @MainActor [weak self] in
                self?.level = peak
                self?.onSamples?(mono, rate)
            }
        }
        tapInstalled = true

        engine.prepare()
        try engine.start()
        isRunning = true
        currentDevice = device
    }

    public func stop() {
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        if engine.isRunning { engine.stop() }
        isRunning = false
        level = 0
    }

    /// Input devices, via CoreAudio — AVCaptureDevice does not report every
    /// virtual device that can carry system audio.
    public static func inputDevices() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            let channels = inputChannelCount(id)
            guard channels > 0 else { return nil }
            guard let uid = stringProperty(id, kAudioDevicePropertyDeviceUID),
                  let name = stringProperty(id, kAudioObjectPropertyName) else { return nil }
            return AudioDevice(id: uid, name: name, deviceID: id, channels: channels)
        }
    }

    private static func inputChannelCount(_ device: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                      alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func stringProperty(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { return nil }
        return value as String?
    }
}

public enum AudioEngineError: Error, CustomStringConvertible {
    case noInputDevice
    case deviceSelectionFailed(OSStatus)
    case invalidFormat
    case permissionDenied

    public var description: String {
        switch self {
        case .noInputDevice: return "no audio input device available"
        case .deviceSelectionFailed(let s): return "could not select that audio input (\(s))"
        case .invalidFormat: return "the audio input reported an unusable format"
        case .permissionDenied:
            return "microphone access is required to read audio, including loopback devices"
        }
    }
}
