import ChordwareCore
import Foundation

enum CLI {
    static func run(_ args: [String]) {
        guard let command = args.first else { printUsage(); exit(0) }
        let rest = Array(args.dropFirst())

        switch command {
        case "analyze", "a": Analyze.run(rest)
        case "chord", "c": Describe.chord(rest)
        case "scales", "s": Describe.scales(rest)
        case "key", "k": Describe.key(rest)
        case "version", "--version", "-v": print("chordware \(ChordwareVersion.current)")
        case "help", "--help", "-h": printUsage()
        default:
            fail("unknown command: \(command)")
        }
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((Style.c("error: ", "1;31") + message + "\n").utf8))
        exit(1)
    }

    static func printUsage() {
        print("""
        \(Style.heading("chordware")) \(Style.dim(ChordwareVersion.current)) \u{2014} harmonic analysis from the command line

        \(Style.bold("USAGE"))
          chordware <command> [arguments]

        \(Style.bold("COMMANDS"))
          analyze <notes|chords>   name a voicing, or analyse a progression
          chord <symbol>           describe one chord: tones, intervals, scales
          scales [query]           browse the scale library
          key <notes|chords>       estimate the key
          version                  print the version

        \(Style.bold("EXAMPLES"))
          \(Style.dim("# name a voicing \u{2014} note names with octaves"))
          chordware analyze C4 E4 G4 B4 D5

          \(Style.dim("# analyse a progression \u{2014} chord symbols"))
          chordware analyze "Dm7 G7 Cmaj7"
          chordware analyze --key Eb "Fm7 Bb7 Ebmaj7"

          \(Style.dim("# explore"))
          chordware chord C7#9
          chordware scales altered --root F#
          chordware key "Cmaj7 Am7 Dm7 G7"
        """)
    }

    /// Pull `--key X` out of an argument list.
    static func extractKey(_ args: inout [String]) -> Key? {
        guard let index = args.firstIndex(where: { $0 == "--key" || $0 == "-k" }),
              index + 1 < args.count else { return nil }
        let value = args[index + 1]
        args.removeSubrange(index...(index + 1))
        return parseKey(value)
    }

    static func parseKey(_ value: String) -> Key? {
        var text = value
        var mode = KeyMode.major
        for suffix in ["minor", "min", "m"] where text.hasSuffix(suffix) && text.count > suffix.count {
            text = String(text.dropLast(suffix.count))
            mode = .minor
            break
        }
        guard let tonic = SpelledNote(text.trimmingCharacters(in: .whitespaces)) else { return nil }
        return Key(tonic: tonic, mode: mode)
    }
}
