import Foundation

@MainActor
func runAll() {
    if ProcessInfo.processInfo.arguments.contains("--diagnose") {
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
    runIslandTests(t)
    runMIDITests(t)
    runMIDIRoutingTests(t)
    runPianoTests(t)
    runKeyboardRangeTests(t)
    runSignalTests(t)
    runMIDIFileTests(t)

    t.summarize()
}

// Program start is already on the main thread; the island tests touch
// main-actor types, so assert that rather than spinning up a runloop.
MainActor.assumeIsolated { runAll() }
