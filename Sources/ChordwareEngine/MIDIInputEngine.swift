import ChordwareCore
import CoreMIDI
import Foundation

public struct MIDIEndpoint: Identifiable, Hashable, Sendable {
    public let id: Int32
    public let name: String
    public let manufacturer: String
    /// True for ports that speak a control-surface protocol rather than music.
    public let isControlSurface: Bool

    public var displayName: String { name }
}

/// Reads notes from attached MIDI hardware.
@MainActor
public final class MIDIInputEngine {
    public private(set) var endpoints: [MIDIEndpoint] = []
    /// Endpoints to listen to. Empty means "choose automatically".
    public var selection: Set<Int32> = [] { didSet { reconnect() } }

    public var onMessage: ((MIDIMessage) -> Void)?
    public var onEndpointsChanged: (([MIDIEndpoint]) -> Void)?

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connected: Set<Int32> = []
    private var started = false

    public init() {}

    /// Ports whose names mark them as control surfaces rather than instruments.
    ///
    /// An Arturia KeyLab exposes four ports, one of which is MCU/HUI. That port
    /// sends note messages for transport buttons and fader touches, so
    /// listening to everything invents chords when you tap Play.
    private static let controlSurfaceMarkers = ["MCU", "HUI", "MACKIE", "CONTROL SURFACE"]

    private static func isControlSurface(name: String) -> Bool {
        let upper = name.uppercased()
        return controlSurfaceMarkers.contains { upper.contains($0) }
    }

    public func start() throws {
        guard !started else { return }

        var status = MIDIClientCreateWithBlock("Chordware" as CFString, &client) { [weak self] notification in
            let messageID = notification.pointee.messageID
            guard messageID == .msgSetupChanged || messageID == .msgObjectAdded
                    || messageID == .msgObjectRemoved else { return }
            Task { @MainActor in self?.refreshEndpoints() }
        }
        guard status == noErr else { throw MIDIEngineError.clientFailed(status) }

        status = MIDIInputPortCreateWithProtocol(
            client, "Chordware In" as CFString, ._1_0, &inputPort
        ) { [weak self] eventListPointer, _ in
            // Runs on CoreMIDI's realtime thread: decode here, deliver on main.
            var messages: [MIDIMessage] = []
            let list = eventListPointer.pointee
            withUnsafePointer(to: list.packet) { firstPacket in
                var packet = firstPacket
                for _ in 0..<Int(list.numPackets) {
                    let wordCount = Int(packet.pointee.wordCount)
                    withUnsafePointer(to: packet.pointee.words) { wordsTuple in
                        wordsTuple.withMemoryRebound(to: UInt32.self, capacity: wordCount) { words in
                            for index in 0..<wordCount {
                                if let message = UMP.decode(word: words[index]) {
                                    messages.append(message)
                                }
                            }
                        }
                    }
                    packet = UnsafePointer(MIDIEventPacketNext(packet))
                }
            }
            guard !messages.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                for message in messages { self.onMessage?(message) }
            }
        }
        guard status == noErr else { throw MIDIEngineError.portFailed(status) }

        started = true
        refreshEndpoints()
    }

    public func stop() {
        guard started else { return }
        for uid in connected { disconnect(uid: uid) }
        connected.removeAll()
        MIDIPortDispose(inputPort)
        MIDIClientDispose(client)
        started = false
    }

    public func refreshEndpoints() {
        var found: [MIDIEndpoint] = []
        for index in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(index)
            var uid: Int32 = 0
            MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &uid)
            let name = Self.stringProperty(source, kMIDIPropertyDisplayName) ?? "Unknown"
            found.append(MIDIEndpoint(
                id: uid,
                name: name,
                manufacturer: Self.stringProperty(source, kMIDIPropertyManufacturer) ?? "",
                isControlSurface: Self.isControlSurface(name: name)
            ))
        }
        endpoints = found
        onEndpointsChanged?(found)
        reconnect()
    }

    /// Endpoints actually listened to for the current selection.
    public var activeEndpoints: [MIDIEndpoint] {
        selection.isEmpty ? endpoints.filter { !$0.isControlSurface }
                          : endpoints.filter { selection.contains($0.id) }
    }

    private func reconnect() {
        guard started else { return }
        let wanted = Set(activeEndpoints.map(\.id))
        for uid in connected.subtracting(wanted) { disconnect(uid: uid) }
        for uid in wanted.subtracting(connected) { connect(uid: uid) }
        connected = wanted
    }

    private func connect(uid: Int32) {
        guard let endpoint = Self.endpoint(for: uid) else { return }
        MIDIPortConnectSource(inputPort, endpoint, nil)
    }

    private func disconnect(uid: Int32) {
        guard let endpoint = Self.endpoint(for: uid) else { return }
        MIDIPortDisconnectSource(inputPort, endpoint)
    }

    private static func endpoint(for uid: Int32) -> MIDIEndpointRef? {
        var object = MIDIObjectRef()
        var type = MIDIObjectType.other
        guard MIDIObjectFindByUniqueID(uid, &object, &type) == noErr else { return nil }
        return object
    }

    static func stringProperty(_ object: MIDIObjectRef, _ property: CFString) -> String? {
        var ref: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, property, &ref) == noErr else { return nil }
        return ref?.takeRetainedValue() as String?
    }
}

public enum MIDIEngineError: Error, CustomStringConvertible {
    case clientFailed(OSStatus)
    case portFailed(OSStatus)
    case virtualSourceFailed(OSStatus)

    public var description: String {
        switch self {
        case .clientFailed(let s): return "could not create a MIDI client (\(s))"
        case .portFailed(let s): return "could not create a MIDI input port (\(s))"
        case .virtualSourceFailed(let s): return "could not publish the virtual MIDI source (\(s))"
        }
    }
}
