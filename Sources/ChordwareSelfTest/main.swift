import Foundation

@MainActor
func runAll() {
    let arguments = ProcessInfo.processInfo.arguments
    if let i = arguments.firstIndex(of: "--audio"), i + 1 < arguments.count {
        probeAudioFile(arguments[i + 1])
        exit(0)
    }
    if arguments.contains("--diagnose") {
        dumpSignalDiagnostics()
        exit(0)
    }
    let t = Harness()

    runPitchTests(t)
    runChordTests(t)
    runParserTests(t)
    runScaleTests(t)
    runAnalysisTests(t)
    runPerformanceTests(t)
    runNamingTests(t)
    runAppTests(t)
    runMIDITests(t)
    runMIDIRoutingTests(t)
    runLiveSessionTests(t)
    runLiveKeyTests(t)
    runPianoTests(t)
    runKeyboardRangeTests(t)
    runSignalTests(t)
    runMIDIFileTests(t)

    t.summarize()
}

// Program start is already on the main thread; the island tests touch
// main-actor types, so assert that rather than spinning up a runloop.
MainActor.assumeIsolated { runAll() }
