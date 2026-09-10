import CoreMIDI
import Foundation

/// Publishes a virtual MIDI source named "Chordware" that any DAW can select,
/// and optionally forwards the incoming keyboard through it.
///
/// Passthrough is what lets Chordware sit inline: point Logic at "Chordware"
/// instead of the keyboard and you get the analysis without giving up the
/// controller, and chords generated from the island arrive on the same port.
@MainActor
public final class MIDIOutputEngine {
    public static let virtualSourceName = "Chordware"

    public private(set) var isRunning = false
    /// Forward everything arriving from the input engine to the virtual source.
    ///
    /// Off by default, and it must stay that way. A DAW typically listens to
    /// *all* MIDI inputs, so with passthrough on it receives every note twice:
    /// once straight from the keyboard and once forwarded by Chordware. Two
    /// voices a few milliseconds apart comb-filter, and the track sounds
    /// broken. Passthrough is only correct when the DAW has been pointed at
    /// Chordware instead of the keyboard, which is a deliberate choice the
    /// player has to make.
    public var passthrough = false

    /// Unique ID of the published source, so the input engine can refuse to
    /// listen to it.
    public private(set) var virtualSourceUID: Int32?

    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    /// Notes this engine started, so they can always be released.
    private var sounding: Set<Int> = []

    public init() {}

    public func start() throws {
        guard !isRunning else { return }
        var status = MIDIClientCreateWithBlock("Chordware Out" as CFString, &client, nil)
        guard status == noErr else { throw MIDIEngineError.clientFailed(status) }

        status = MIDISourceCreateWithProtocol(client, Self.virtualSourceName as CFString, ._1_0, &source)
        guard status == noErr else { throw MIDIEngineError.virtualSourceFailed(status) }

        var uid: Int32 = 0
        if MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &uid) == noErr {
            virtualSourceUID = uid
        }
        isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        allNotesOff()
        MIDIEndpointDispose(source)
        MIDIClientDispose(client)
        virtualSourceUID = nil
        isRunning = false
    }

    public func send(_ message: MIDIMessage) {
        guard isRunning else { return }
        var word = UMP.encode(message)
        var list = MIDIEventList()
        let packet = MIDIEventListInit(&list, ._1_0)
        _ = MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet,
                             mach_absolute_time(), 1, &word)
        MIDIReceivedEventList(source, &list)
    }

    /// Forward an incoming message, when passthrough is on.
    public func forward(_ message: MIDIMessage) {
        guard passthrough else { return }
        send(message)
    }

    public func playChord(notes: [Int], velocity: Int = 90, channel: Int = 0) {
        for note in notes {
            send(.noteOn(note: note, velocity: velocity, channel: channel))
            sounding.insert(note)
        }
    }

    public func releaseChord(notes: [Int], channel: Int = 0) {
        for note in notes {
            send(.noteOff(note: note, channel: channel))
            sounding.remove(note)
        }
    }

    /// Release everything this engine started. Called on stop so a crash or a
    /// quit mid-chord cannot leave a note hanging in the DAW.
    public func allNotesOff(channel: Int = 0) {
        for note in sounding { send(.noteOff(note: note, channel: channel)) }
        sounding.removeAll()
        send(.allNotesOff(channel: channel))
    }
}
