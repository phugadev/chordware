import ChordwareCore
import Foundation
import ChordwareEngine
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

        t.test("the detail reveal is monotonic and drives the panel height") {
            let g = ScreenGeometry(notchWidth: 185, notchHeight: 32,
                                   isPhysical: true, screenFrame: screen)
            let collapsed = IslandRootView.detailHeight(for: .glance)
            let expanded = IslandRootView.detailHeight(for: .expanded)
            let act = IslandRootView.detailHeight(for: .act)

            t.equal(collapsed, 0, "nothing revealed while collapsed")
            t.check(expanded > collapsed, "expanding reveals detail")
            t.check(act > expanded, "acting reveals more, it does not swap")

            // Panel height must be exactly the notch strip plus what is
            // revealed; if these drift apart the clip and the shape disagree
            // and the panel starts cross-fading again.
            for state in [IslandState.glance, .expanded, .act] {
                t.equal(IslandRootView.size(for: state, geometry: g).height,
                        g.notchHeight + IslandRootView.detailHeight(for: state),
                        "height matches reveal for \(state)")
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

func runMIDITests(_ t: Harness) {
    t.suite("MIDI decoding") {
        t.test("channel voice messages round-trip through UMP words") {
            let cases: [MIDIMessage] = [
                .noteOn(note: 60, velocity: 100, channel: 0),
                .noteOn(note: 127, velocity: 1, channel: 15),
                .noteOff(note: 48, channel: 3),
                .sustain(down: true, channel: 0),
                .sustain(down: false, channel: 9),
                .allNotesOff(channel: 2),
            ]
            for message in cases {
                t.equal(UMP.decode(word: UMP.encode(message)), message, "\(message)")
            }
        }

        t.test("a note-on with zero velocity decodes as a note-off") {
            // Running-status hardware sends this instead of 0x80. Decoding it
            // as a note-on leaves the chord stuck on screen forever.
            let word = UMP.encode(.noteOn(note: 60, velocity: 100, channel: 0)) & 0xFFFFFF00
            t.equal(UMP.decode(word: word), .noteOff(note: 60, channel: 0), "zero velocity")
        }

        t.test("non-note traffic is ignored rather than guessed at") {
            // Modulation wheel, and a system message.
            let modWheel = (UInt32(0x2) << 28) | (UInt32(0xB) << 20) | (UInt32(1) << 8) | 64
            t.check(UMP.decode(word: modWheel) == nil, "CC1 is not harmony")
            let utility = UInt32(0x0) << 28
            t.check(UMP.decode(word: utility) == nil, "utility messages ignored")
            let sysex = UInt32(0x3) << 28
            t.check(UMP.decode(word: sysex) == nil, "sysex ignored")
        }
    }
}

func runMIDIRoutingTests(_ t: Harness) {
    func endpoint(_ id: Int32, _ name: String, control: Bool = false) -> MIDIEndpoint {
        MIDIEndpoint(id: id, name: name, manufacturer: "Test", isControlSurface: control)
    }

    t.suite("MIDI routing") {
        let keyboard = endpoint(1, "KL Essential 49 mk3 MIDI")
        let dinThru = endpoint(2, "KL Essential 49 mk3 DINTHRU")
        let mcu = endpoint(3, "KL Essential 49 mk3 MCU/HUI", control: true)
        let ownSource = endpoint(99, "Chordware")
        let all = [keyboard, dinThru, mcu, ownSource]

        t.test("our own virtual source is never listened to") {
            // Chordware publishes "Chordware" for passthrough. Listening to it
            // feeds every forwarded message back into the input, which forwards
            // it again -- a loop that floods the DAW within a second.
            let chosen = MIDIInputEngine.chooseEndpoints(from: all, selection: [], excluded: [99])
            t.check(!chosen.contains { $0.id == 99 }, "excluded by default selection")

            // Even an explicit selection must not be able to create the loop.
            let forced = MIDIInputEngine.chooseEndpoints(from: all, selection: [99], excluded: [99])
            t.check(forced.isEmpty, "excluded even when explicitly selected")
        }

        t.test("control surfaces are skipped unless asked for") {
            let auto = MIDIInputEngine.chooseEndpoints(from: all, selection: [], excluded: [99])
            t.equal(auto.map(\.id), [1, 2], "MCU/HUI left out of the automatic choice")

            let explicit = MIDIInputEngine.chooseEndpoints(from: all, selection: [3], excluded: [99])
            t.equal(explicit.map(\.id), [3], "but available when chosen deliberately")
        }

        t.test("an explicit selection wins over the default") {
            let chosen = MIDIInputEngine.chooseEndpoints(from: all, selection: [1], excluded: [99])
            t.equal(chosen.map(\.id), [1], "only the keyboard")
        }
    }
}

@MainActor
func runPianoTests(_ t: Harness) {
    t.suite("Piano layout") {
        // Four octaves from C2, the island's default.
        let layout = PianoLayout(lowNote: 36, octaves: 4, size: CGSize(width: 290, height: 42))

        t.test("white keys are the naturals, in order") {
            t.equal(layout.whiteCount, 29, "four octaves plus the final C")
            t.equal(layout.whiteKeys.count, 29, "one rect each")
            t.equal(layout.whiteKeys.first?.note, 36, "starts on C2")
            t.equal(layout.whiteKeys.last?.note, 84, "ends on C6")
            // C D E F G A B, then the next C.
            t.equal(layout.whiteKeys.prefix(8).map(\.note), [36, 38, 40, 41, 43, 45, 47, 48],
                    "first octave of naturals")
            // No white key may be a black note.
            let blackPitchClasses = Set([1, 3, 6, 8, 10])
            t.check(layout.whiteKeys.allSatisfy { !blackPitchClasses.contains(PitchClass($0.note).value) },
                    "no accidental is drawn as a white key")
        }

        t.test("black keys are the accidentals, and there are the right number") {
            t.equal(layout.blackKeys.count, 20, "five per octave")
            let blackPitchClasses = Set([1, 3, 6, 8, 10])
            t.check(layout.blackKeys.allSatisfy { blackPitchClasses.contains(PitchClass($0.note).value) },
                    "every black key is an accidental")
            // The E/F and B/C boundaries must stay empty.
            t.check(!layout.blackKeys.contains { PitchClass($0.note).value == 5 }, "no black key on F")
            t.check(!layout.blackKeys.contains { PitchClass($0.note).value == 0 }, "no black key on C")
        }

        t.test("every note maps to exactly one key") {
            for note in layout.noteRange {
                let matches = layout.keys.filter { $0.note == note }
                t.equal(matches.count, 1, "note \(MIDINote.name(note)) has one key")
            }
        }

        t.test("key positions rise with pitch") {
            // The real bug this guards: a keyboard whose highlighting is offset
            // from the notes played. Centres must be strictly increasing.
            let sorted = layout.keys.sorted { $0.note < $1.note }
            for (a, b) in zip(sorted, sorted.dropFirst()) {
                t.check(a.rect.midX < b.rect.midX,
                        "\(MIDINote.name(a.note)) sits left of \(MIDINote.name(b.note))")
            }
        }

        t.test("black keys straddle the right white keys") {
            let whites = layout.whiteKeys
            for black in layout.blackKeys {
                // The white key a semitone below and the one a semitone above.
                guard let below = whites.first(where: { $0.note == black.note - 1 }),
                      let above = whites.first(where: { $0.note == black.note + 1 }) else {
                    t.check(false, "missing neighbours for \(MIDINote.name(black.note))")
                    continue
                }
                t.check(black.rect.midX > below.rect.minX && black.rect.midX < above.rect.maxX,
                        "\(MIDINote.name(black.note)) sits between its neighbours")
                // And is centred on the seam between them.
                let seam = below.rect.maxX
                t.check(abs(black.rect.midX - seam) < 0.01,
                        "\(MIDINote.name(black.note)) is centred on the seam")
            }
        }
    }
}

@MainActor
func runKeyboardRangeTests(_ t: Harness) {
    t.suite("Keyboard range") {
        func range() -> KeyboardRange {
            let suite = UserDefaults(suiteName: "ChordwareTests-\(UUID().uuidString)")!
            let r = KeyboardRange(defaults: suite)
            r.use(device: "Test Controller")
            return r
        }

        t.test("a note outside the view widens it, and nothing moves") {
            let r = range()
            t.equal(r.lowNote, 36, "starts at C2")
            t.equal(r.highNote, 84, "ends at C6")

            t.check(r.observe([24]), "a low C1 widens the range")
            t.equal(r.lowNote, 24, "downwards")
            t.equal(r.highNote, 84, "and the top edge is untouched")
        }

        t.test("the keyboard never slides") {
            // The bug this replaces: one high note slid the whole instrument up
            // an octave, so every note already on screen changed position. A
            // keyboard is a map; middle C has to stay where it was.
            let r = range()
            let low = r.lowNote

            t.check(!r.observe([50, 53, 57]), "playing inside the view changes nothing")
            t.equal(r.lowNote, low, "left edge unmoved")

            r.observe([89])
            t.equal(r.lowNote, low, "a high note does not move the left edge")
            t.check(r.highNote >= 89, "but it does become visible")

            r.observe([50, 53, 57])
            t.equal(r.lowNote, low, "and coming back down moves nothing either")
        }

        t.test("it never shrinks back") {
            let r = range()
            r.observe([24])
            let widened = r.octaves
            for _ in 0..<20 { r.observe([60, 64, 67]) }
            t.equal(r.octaves, widened, "staying in the middle does not narrow it")
        }

        t.test("widening stops before the keys become slivers") {
            let r = range()
            r.observe([0, 127])
            t.check(r.octaves <= 7, "capped, got \(r.octaves)")
        }

        t.test("the fitted range is remembered per device") {
            let suite = UserDefaults(suiteName: "ChordwareTests-\(UUID().uuidString)")!
            let first = KeyboardRange(defaults: suite)
            first.use(device: "Controller A")
            first.observe([24])
            t.equal(first.lowNote, 24, "learned")

            let second = KeyboardRange(defaults: suite)
            second.use(device: "Controller A")
            t.equal(second.lowNote, first.lowNote, "remembered next session")
            t.equal(second.highNote, first.highNote, "both edges")

            second.use(device: "Controller B")
            t.equal(second.lowNote, 36, "a different device starts fresh")
        }
    }
}
