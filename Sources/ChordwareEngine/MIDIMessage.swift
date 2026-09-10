import Foundation

/// The subset of MIDI that matters for reading harmony.
public enum MIDIMessage: Sendable, Equatable {
    case noteOn(note: Int, velocity: Int, channel: Int)
    case noteOff(note: Int, channel: Int)
    case sustain(down: Bool, channel: Int)
    case allNotesOff(channel: Int)
}

/// Universal MIDI Packet words in and out.
///
/// Pure functions, so the bit-twiddling can be tested without a keyboard
/// attached — which is most of what goes wrong here.
///
/// A MIDI 1.0 channel-voice word packs: message type and group in the top
/// byte, status and channel in the next, then two data bytes.
public enum UMP {
    public static func decode(word: UInt32) -> MIDIMessage? {
        let messageType = UInt8((word >> 28) & 0xF)
        // 0x2 is MIDI 1.0 Channel Voice: one message per 32-bit word.
        guard messageType == 0x2 else { return nil }

        let status = UInt8((word >> 20) & 0xF)
        let channel = Int((word >> 16) & 0xF)
        let data1 = Int((word >> 8) & 0x7F)
        let data2 = Int(word & 0x7F)

        switch status {
        case 0x9:
            // A note-on with zero velocity is a note-off; hardware using
            // running status sends it constantly.
            return data2 == 0
                ? .noteOff(note: data1, channel: channel)
                : .noteOn(note: data1, velocity: data2, channel: channel)
        case 0x8:
            return .noteOff(note: data1, channel: channel)
        case 0xB:
            switch data1 {
            case 64: return .sustain(down: data2 >= 64, channel: channel)
            // 120 all sound off, 123 all notes off.
            case 120, 123: return .allNotesOff(channel: channel)
            default: return nil
            }
        default:
            return nil
        }
    }

    public static func encode(_ message: MIDIMessage, group: Int = 0) -> UInt32 {
        func word(_ status: UInt32, _ channel: Int, _ data1: Int, _ data2: Int) -> UInt32 {
            (UInt32(0x2) << 28)
                | (UInt32(group & 0xF) << 24)
                | (status << 20)
                | (UInt32(channel & 0xF) << 16)
                | (UInt32(data1 & 0x7F) << 8)
                | UInt32(data2 & 0x7F)
        }
        switch message {
        case .noteOn(let note, let velocity, let channel):
            return word(0x9, channel, note, velocity)
        case .noteOff(let note, let channel):
            return word(0x8, channel, note, 0)
        case .sustain(let down, let channel):
            return word(0xB, channel, 64, down ? 127 : 0)
        case .allNotesOff(let channel):
            return word(0xB, channel, 123, 0)
        }
    }
}
