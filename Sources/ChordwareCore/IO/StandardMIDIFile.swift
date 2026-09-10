import Foundation

/// Reads and writes Standard MIDI Files, with no dependencies.
///
/// Only the parts a performance needs: a tempo, a track name, and notes. Enough
/// to hand what you played to a DAW, and enough to read one back so the writer
/// can be tested against its own output rather than trusted.
public enum StandardMIDIFile {
    public struct Note: Equatable, Sendable {
        public let note: Int
        public let velocity: Int
        public let startTick: Int
        public let durationTicks: Int
        public let channel: Int

        public init(note: Int, velocity: Int, startTick: Int, durationTicks: Int, channel: Int = 0) {
            self.note = note
            self.velocity = velocity
            self.startTick = startTick
            self.durationTicks = durationTicks
            self.channel = channel
        }

        public var endTick: Int { startTick + durationTicks }
    }

    /// Pulses per quarter note. 480 is what most DAWs use.
    public static let defaultTicksPerQuarter = 480

    // MARK: - Writing

    public static func data(notes: [Note],
                            ticksPerQuarter: Int = defaultTicksPerQuarter,
                            tempo: Double = 120,
                            name: String? = nil) -> Data {
        var file = Data()
        file.append(contentsOf: Array("MThd".utf8))
        file.append(uint32: 6)
        file.append(uint16: 1)                      // format 1
        file.append(uint16: 1)                      // one track
        file.append(uint16: UInt16(ticksPerQuarter))

        var track = Data()
        if let name, !name.isEmpty {
            let bytes = Array(name.utf8)
            track.append(variableLength: 0)
            track.append(contentsOf: [0xFF, 0x03])
            track.append(variableLength: bytes.count)
            track.append(contentsOf: bytes)
        }

        // Tempo, in microseconds per quarter note.
        let microseconds = Int(60_000_000.0 / max(1, tempo))
        track.append(variableLength: 0)
        track.append(contentsOf: [0xFF, 0x51, 0x03])
        track.append(contentsOf: [UInt8((microseconds >> 16) & 0xFF),
                                  UInt8((microseconds >> 8) & 0xFF),
                                  UInt8(microseconds & 0xFF)])

        // Note-ons and note-offs interleaved in tick order. A held chord and a
        // melody over it produce overlapping notes, so these cannot simply be
        // written note by note.
        struct Event { let tick: Int; let isOn: Bool; let note: Note }
        var events: [Event] = []
        for note in notes {
            events.append(Event(tick: note.startTick, isOn: true, note: note))
            events.append(Event(tick: max(note.startTick, note.endTick), isOn: false, note: note))
        }
        // Note-offs before note-ons at the same tick, so a repeated note is
        // released before it is struck again.
        events.sort { ($0.tick, $0.isOn ? 1 : 0) < ($1.tick, $1.isOn ? 1 : 0) }

        var previousTick = 0
        for event in events {
            track.append(variableLength: max(0, event.tick - previousTick))
            previousTick = event.tick
            let status: UInt8 = (event.isOn ? 0x90 : 0x80) | UInt8(event.note.channel & 0x0F)
            track.append(contentsOf: [status,
                                      UInt8(clamping: event.note.note),
                                      UInt8(clamping: event.isOn ? event.note.velocity : 0)])
        }

        track.append(variableLength: 0)
        track.append(contentsOf: [0xFF, 0x2F, 0x00])   // end of track

        file.append(contentsOf: Array("MTrk".utf8))
        file.append(uint32: UInt32(track.count))
        file.append(track)
        return file
    }

    // MARK: - Reading

    public struct Contents: Equatable, Sendable {
        public let notes: [Note]
        public let ticksPerQuarter: Int
        public let tempo: Double
        public let name: String?
    }

    public static func read(_ data: Data) -> Contents? {
        var reader = Reader(data)
        guard reader.string(4) == "MThd", let headerLength = reader.uint32(),
              headerLength >= 6, reader.uint16() != nil,
              let trackCount = reader.uint16(), let division = reader.uint16() else { return nil }
        // Skip any header bytes beyond the six we understand.
        reader.skip(Int(headerLength) - 6)

        var notes: [Note] = []
        var tempo = 120.0
        var name: String?

        for _ in 0..<trackCount {
            guard reader.string(4) == "MTrk", let length = reader.uint32() else { break }
            let end = reader.offset + Int(length)
            var tick = 0
            var status: UInt8 = 0
            var pending: [Int: (tick: Int, velocity: Int, channel: Int)] = [:]

            while reader.offset < end, let delta = reader.variableLength() {
                tick += delta
                guard var byte = reader.byte() else { break }
                if byte < 0x80 {
                    // Running status: reuse the last status byte.
                    reader.rewind(1)
                    byte = status
                } else {
                    status = byte
                }

                switch byte & 0xF0 {
                case 0x90, 0x80:
                    guard let note = reader.byte(), let velocity = reader.byte() else { break }
                    let channel = Int(byte & 0x0F)
                    if byte & 0xF0 == 0x90, velocity > 0 {
                        pending[Int(note)] = (tick, Int(velocity), channel)
                    } else if let start = pending.removeValue(forKey: Int(note)) {
                        notes.append(Note(note: Int(note), velocity: start.velocity,
                                          startTick: start.tick,
                                          durationTicks: tick - start.tick,
                                          channel: start.channel))
                    }
                case 0xA0, 0xB0, 0xE0:
                    reader.skip(2)
                case 0xC0, 0xD0:
                    reader.skip(1)
                case 0xF0:
                    if byte == 0xFF {
                        guard let type = reader.byte(), let length = reader.variableLength() else { break }
                        if type == 0x51, length == 3,
                           let a = reader.byte(), let b = reader.byte(), let c = reader.byte() {
                            let micros = (Int(a) << 16) | (Int(b) << 8) | Int(c)
                            if micros > 0 { tempo = 60_000_000.0 / Double(micros) }
                        } else if type == 0x03 {
                            name = reader.string(length)
                        } else {
                            reader.skip(length)
                        }
                    } else if byte == 0xF0 || byte == 0xF7 {
                        if let length = reader.variableLength() { reader.skip(length) }
                    }
                default:
                    break
                }
            }
            reader.offset = end
        }

        return Contents(notes: notes.sorted { ($0.startTick, $0.note) < ($1.startTick, $1.note) },
                        ticksPerQuarter: Int(division), tempo: tempo, name: name)
    }

    private struct Reader {
        let data: Data
        var offset: Int

        init(_ data: Data) {
            self.data = data
            offset = data.startIndex
        }

        mutating func byte() -> UInt8? {
            guard offset < data.endIndex else { return nil }
            defer { offset += 1 }
            return data[offset]
        }

        mutating func rewind(_ count: Int) { offset = max(data.startIndex, offset - count) }
        mutating func skip(_ count: Int) { offset = min(data.endIndex, offset + max(0, count)) }

        mutating func uint16() -> UInt16? {
            guard let a = byte(), let b = byte() else { return nil }
            return (UInt16(a) << 8) | UInt16(b)
        }

        mutating func uint32() -> UInt32? {
            guard let a = byte(), let b = byte(), let c = byte(), let d = byte() else { return nil }
            return (UInt32(a) << 24) | (UInt32(b) << 16) | (UInt32(c) << 8) | UInt32(d)
        }

        mutating func string(_ count: Int) -> String? {
            var bytes: [UInt8] = []
            for _ in 0..<count { guard let b = byte() else { return nil }; bytes.append(b) }
            return String(bytes: bytes, encoding: .utf8)
        }

        /// MIDI's variable-length quantity: seven bits per byte, top bit
        /// signalling that another byte follows.
        mutating func variableLength() -> Int? {
            var value = 0
            for _ in 0..<4 {
                guard let b = byte() else { return nil }
                value = (value << 7) | Int(b & 0x7F)
                if b & 0x80 == 0 { return value }
            }
            return value
        }
    }
}

private extension Data {
    mutating func append(uint16 value: UInt16) {
        append(contentsOf: [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }

    mutating func append(uint32 value: UInt32) {
        append(contentsOf: [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
                            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }

    mutating func append(variableLength value: Int) {
        var buffer = [UInt8(value & 0x7F)]
        var remaining = value >> 7
        while remaining > 0 {
            buffer.insert(UInt8((remaining & 0x7F) | 0x80), at: 0)
            remaining >>= 7
        }
        append(contentsOf: buffer)
    }
}
