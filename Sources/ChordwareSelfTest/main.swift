import Foundation

@MainActor
func runAll() {
    let t = Harness()

    runPitchTests(t)
    runChordTests(t)
    runParserTests(t)
    runScaleTests(t)
    runAnalysisTests(t)
    runIslandTests(t)

    t.summarize()
}

// Program start is already on the main thread; the island tests touch
// main-actor types, so assert that rather than spinning up a runloop.
MainActor.assumeIsolated { runAll() }
