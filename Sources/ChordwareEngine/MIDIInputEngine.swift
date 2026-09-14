import ChordwareCore
import CoreMIDI
import Foundation

public struct MIDIEndpoint: Identifiable, Hashable, Sendable {
    public let id: Int32
    public let name: String
    public let manufacturer: String
    /// True for ports that speak a control-surface protocol rather than music.
    public let isControlSurface: Bool
    /// True for software ports published by other apps rather than hardware.
    public let isVirtual: Bool

    public var displayName: String { name }

    public init(id: Int32, name: String, manufacturer: String,
                isControlSurface: Bool, isVirtual: Bool = false) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.isControlSurface = isControlSurface
        self.isVirtual = isVirtual
    }
}

/// Reads notes from attached MIDI hardware.
@MainActor
public final class MIDIInputEngine {
    public private(set) var endpoints: [MIDIEndpoint] = []
    /// Endpoints to listen to. Empty means "choose automatically".
    public var selection: Set<Int32> = [] { didSet { reconnect() } }
    /// Endpoints that must never be listened to, whatever the selection says.
    ///
    /// Chordware publishes its own virtual source for passthrough, and that
    /// source appears in the system's source list like any other. Listening to
    /// it feeds every forwarded message straight back into the input, which
    /// forwards it again -- a loop that floods the DAW within a second.
    public var excluded: Set<Int32> = [] { didSet { refreshEndpoints() } }

    public var onMessage: ((MIDIMessage) -> Void)?
    public var onEndpointsChanged: (([MIDIEndpoint]) -> Void)?
    /// The endpoint that most recently sent a note, which is the only reliable
    /// answer to "what am I playing on".
    public private(set) var lastActiveEndpointID: Int32?
    public var onActiveEndpointChanged: ((MIDIEndpoint?) -> Void)?

    public var lastActiveEndpoint: MIDIEndpoint? {
        lastActiveEndpointID.flatMap { id in endpoints.first { $0.id == id } }
    }

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connected: Set<Int32> = []
    /// One heap slot per connection, holding the endpoint's id, handed to
    /// CoreMIDI as the connection refCon so arriving events can be attributed.
    private var connectionTokens: [Int32: UnsafeMutablePointer<Int32>] = [:]
    private var started = false

    public init() {}

    /// Decode every message in one delivery from CoreMIDI.
    ///
    /// Walked in place, deliberately. The obvious version copies
    /// `pointee.packet` to the stack and walks that, which is correct only
    /// while the whole list fits inside one MIDIEventPacket's storage -- 64
    /// words. A list is variable-length and its later packets live past that,
    /// so walking the copy reads off the end of it: a run of a couple of
    /// octaves arriving in one delivery segfaulted the app on CoreMIDI's
    /// realtime thread, with nothing on screen to say why.
    /// `nonisolated` because CoreMIDI calls it on its realtime thread, which is
    /// not the main actor and must not wait for it.
    nonisolated public static func decode(eventList: UnsafePointer<MIDIEventList>) -> [MIDIMessage] {
        guard let packetOffset = MemoryLayout<MIDIEventList>.offset(of: \.packet),
              let wordsOffset = MemoryLayout<MIDIEventPacket>.offset(of: \.words)
        else { return [] }

        var messages: [MIDIMessage] = []
        var packet = UnsafeRawPointer(eventList)
            .advanced(by: packetOffset)
            .assumingMemoryBound(to: MIDIEventPacket.self)
        for _ in 0..<Int(eventList.pointee.numPackets) {
            let wordCount = Int(packet.pointee.wordCount)
            let words = UnsafeRawPointer(packet)
                .advanced(by: wordsOffset)
                .assumingMemoryBound(to: UInt32.self)
            for index in 0..<wordCount {
                if let message = UMP.decode(word: words[index]) { messages.append(message) }
            }
            packet = UnsafePointer(MIDIEventPacketNext(packet))
        }
        return messages
    }

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
        ) { [weak self] eventListPointer, sourceRefCon in
            let sourceUID = sourceRefCon?.assumingMemoryBound(to: Int32.self).pointee
            // Runs on CoreMIDI's realtime thread: decode here, deliver on main.
            let messages = MIDIInputEngine.decode(eventList: eventListPointer)
            guard !messages.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let sourceUID, case .noteOn = messages.first, self.lastActiveEndpointID != sourceUID {
                    self.lastActiveEndpointID = sourceUID
                    self.onActiveEndpointChanged?(self.lastActiveEndpoint)
                }
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
            // A virtual endpoint has no entity behind it; hardware does. That
            // is how "Logic Pro Virtual Out" is told apart from a keyboard.
            var entity = MIDIEntityRef()
            let isVirtual = MIDIEndpointGetEntity(source, &entity) != noErr
            found.append(MIDIEndpoint(
                id: uid,
                name: name,
                manufacturer: Self.stringProperty(source, kMIDIPropertyManufacturer) ?? "",
                isControlSurface: Self.isControlSurface(name: name),
                isVirtual: isVirtual
            ))
        }
        endpoints = found.filter { !excluded.contains($0.id) }
        onEndpointsChanged?(endpoints)
        reconnect()
    }

    /// Endpoints actually listened to for the current selection.
    public var activeEndpoints: [MIDIEndpoint] {
        Self.chooseEndpoints(from: endpoints, selection: selection, excluded: excluded)
    }

    /// Which endpoints to listen to. Pure, so both the feedback exclusion and
    /// the control-surface default are testable without hardware.
    nonisolated public static func chooseEndpoints(from all: [MIDIEndpoint],
                                       selection: Set<Int32>,
                                       excluded: Set<Int32>) -> [MIDIEndpoint] {
        let available = all.filter { !excluded.contains($0.id) }
        guard selection.isEmpty else {
            return available.filter { selection.contains($0.id) }
        }
        // With no explicit choice, listen to instruments but not control
        // surfaces: those send notes for transport buttons and faders.
        return available.filter { !$0.isControlSurface }
    }

    private func reconnect() {
        guard started else { return }
        let wanted = Set(activeEndpoints.map(\.id))
        for uid in connected.subtracting(wanted) { disconnect(uid: uid) }
        for uid in wanted.subtracting(connected) { connect(uid: uid) }
        connected = wanted
    }

    private func connect(uid: Int32) {
        guard let endpoint = Self.endpoint(for: uid), connectionTokens[uid] == nil else { return }
        let token = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        token.initialize(to: uid)
        connectionTokens[uid] = token
        MIDIPortConnectSource(inputPort, endpoint, token)
    }

    private func disconnect(uid: Int32) {
        if let endpoint = Self.endpoint(for: uid) {
            MIDIPortDisconnectSource(inputPort, endpoint)
        }
        if let token = connectionTokens.removeValue(forKey: uid) {
            token.deinitialize(count: 1)
            token.deallocate()
        }
        if lastActiveEndpointID == uid {
            lastActiveEndpointID = nil
            onActiveEndpointChanged?(nil)
        }
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
