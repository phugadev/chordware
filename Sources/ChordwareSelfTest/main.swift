import Foundation

@MainActor
func runAll() {
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
    runMIDIFileTests(t)

    t.summarize()
}

// Program start is already on the main thread; the window tests touch
// main-actor types, so assert that rather than spinning up a runloop.
MainActor.assumeIsolated { runAll() }
