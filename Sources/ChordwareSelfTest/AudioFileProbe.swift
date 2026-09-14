import AVFoundation
import ChordwareCore
import ChordwareSignal
import Foundation

/// Run a real audio file through the same extractor and tracker the live
/// listener uses, and print what it hears.
///
/// The signal tests feed the chain synthesised tones, which is the right way to
/// check the maths and no way at all to know whether it works on music. This is
/// how that question gets answered: `chordware-selftest --audio <file>`.
func probeAudioFile(_ path: String) {
    let url = URL(fileURLWithPath: path)
    guard let file = try? AVAudioFile(forReading: url) else {
        print("could not read \(path)"); exit(1)
    }
    let rate = file.processingFormat.sampleRate
    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                        frameCapacity: AVAudioFrameCount(file.length)),
          (try? file.read(into: buffer)) != nil,
          let channels = buffer.floatChannelData else {
        print("could not decode \(path)"); exit(1)
    }

    // Mono sum, which is what the live engine hands the extractor.
    let frames = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    var mono = [Float](repeating: 0, count: frames)
    for c in 0..<channelCount {
        for i in 0..<frames { mono[i] += channels[c][i] / Float(channelCount) }
    }

    guard let extractor = ChromaExtractor(configuration: .init(sampleRate: rate)) else {
        print("could not build extractor"); exit(1)
    }
    let tracker = AudioChordTracker()
    print("\(path)  \(Int(rate)) Hz  \(String(format: "%.1f", Double(frames) / rate))s\n")

    var last: String?
    let hop = extractor.configuration.hopSize
    var offset = 0
    while offset + extractor.configuration.frameSize <= frames {
        let block = Array(mono[offset..<(offset + hop)])
        for frame in extractor.process(samples: block) {
            tracker.observe(frame)
            let name = tracker.chord?.symbol()
            if name != last, let name {
                let t = Double(offset) / rate
                let voices = frame.notes.map { MIDINote.name($0) }.joined(separator: " ")
                print(String(format: "  %6.2fs  %-10s  %@", t, (name as NSString).utf8String!,
                             voices as NSString))
                last = name
            }
        }
        offset += hop
    }
}
