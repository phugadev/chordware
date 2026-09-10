import ChordwareCore
import ChordwareIsland
import CoreGraphics

@MainActor
func runIslandTests(_ t: Harness) {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    t.suite("Island geometry") {
        t.test("a screen with no notch falls back to the pill") {
            let virtual = ScreenGeometry(notchWidth: 200, notchHeight: 32,
                                         isPhysical: false, screenFrame: screen)
            t.check(!virtual.isPhysical, "flagged as virtual")
            t.equal(virtual.notchWidth, ScreenGeometry.virtualNotchSize.width, "pill width")
        }

        t.test("the window is centred on the notch and pinned to the top") {
            let g = ScreenGeometry(notchWidth: 200, notchHeight: 32,
                                   isPhysical: true, screenFrame: screen)
            let frame = g.windowFrame(contentSize: CGSize(width: 600, height: 400))
            t.equal(frame.midX, screen.midX, "horizontally centred")
            t.equal(frame.maxY, screen.maxY, "flush with the top of the screen")
            t.equal(frame.height, 400, "height honoured")

            // Never narrower than the notch it has to cover.
            let small = g.windowFrame(contentSize: CGSize(width: 10, height: 4))
            t.equal(small.width, 200, "clamped to notch width")
            t.equal(small.height, 32, "clamped to notch height")
        }

        t.test("states grow monotonically, and always cover the notch") {
            let g = ScreenGeometry(notchWidth: 200, notchHeight: 32,
                                   isPhysical: true, screenFrame: screen)
            let idle = IslandRootView.size(for: .idle, geometry: g)
            let glance = IslandRootView.size(for: .glance, geometry: g)
            let expanded = IslandRootView.size(for: .expanded, geometry: g)
            let act = IslandRootView.size(for: .act, geometry: g)

            t.check(idle.width <= glance.width, "glance is at least as wide as idle")
            t.check(glance.width <= expanded.width, "expanded is wider than glance")
            t.check(expanded.width <= act.width, "act is widest")
            t.check(glance.height <= expanded.height, "expanded is taller than glance")
            t.check(expanded.height <= act.height, "act is tallest")

            for size in [idle, glance, expanded, act] {
                t.check(size.width >= g.notchWidth, "never narrower than the notch")
                t.check(size.height >= g.notchHeight, "never shorter than the notch")
            }
        }

        t.test("the notch shape stays inside its bounds at any size") {
            // The shape mixes convex and concave corners, so a bad radius clamp
            // shows up as a path that escapes its own rect.
            for size in [CGSize(width: 200, height: 32), CGSize(width: 40, height: 8),
                         CGSize(width: 600, height: 240), CGSize(width: 12, height: 40)] {
                let rect = CGRect(origin: .zero, size: size)
                let bounds = NotchShape(topRadius: 9, bottomRadius: 20).path(in: rect).boundingRect
                t.check(bounds.minX >= rect.minX - 0.01 && bounds.maxX <= rect.maxX + 0.01,
                        "horizontal bounds at \(Int(size.width))x\(Int(size.height))")
                t.check(bounds.minY >= rect.minY - 0.01 && bounds.maxY <= rect.maxY + 0.01,
                        "vertical bounds at \(Int(size.width))x\(Int(size.height))")
            }
        }
    }

    t.suite("Island model") {
        t.test("a new chord does not close a panel the player is reading") {
            let model = IslandModel()
            let notes = MIDINote.parseList("C4 E4 G4")!
            model.present(candidates: ChordDetector.detect(midiNotes: notes),
                          heldNotes: notes, atMs: 0)
            t.equal(model.state, .glance, "playing opens the glance state")

            model.state = .expanded
            let next = MIDINote.parseList("D4 F4 A4")!
            model.present(candidates: ChordDetector.detect(midiNotes: next),
                          heldNotes: next, atMs: 1000)
            t.equal(model.state, .expanded, "stays expanded while hovered")
            t.equal(model.chord?.symbol(), "Dm", "but the chord still updates")
        }

        t.test("releasing every note returns to idle and closes the event") {
            let model = IslandModel()
            let notes = MIDINote.parseList("C4 E4 G4")!
            model.present(candidates: ChordDetector.detect(midiNotes: notes),
                          heldNotes: notes, atMs: 0)
            model.clearNotes(atMs: 1200)
            t.equal(model.state, .idle, "back to idle")
            t.check(model.heldNotes.isEmpty, "no notes held")
            t.equal(model.progression.events.first?.durationMs, 1200, "event closed with a duration")
        }

        t.test("preview data populates every surface the island renders") {
            let model = IslandPreviewData.model(state: .expanded)
            t.check(model.chord != nil, "has a chord")
            t.check(!model.alternatives.isEmpty, "has alternatives")
            t.check(model.key != nil, "has a key")
            t.check(model.romanNumeral != nil, "has a roman numeral")
            t.check(!model.progression.isEmpty, "has a progression")
            t.check(!model.scaleFits.isEmpty, "has scale suggestions")
        }
    }
}
