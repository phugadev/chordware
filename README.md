# Chordware

A harmonic analysis platform that lives in your Mac's notch.

Play, and the notch tells you what you played — the chord, its inversion, the key
you're in, and the Roman numeral. Hover, and it opens into the detail. It reads
your MIDI keyboard **or any audio your Mac can hear**, so it works on a Logic
bounce, a DJ deck, a YouTube video or a mic'd guitar just as well as on a
controller.

Free, MIT-licensed, no accounts, no telemetry, nothing leaves your machine.

## Why

[Chordwatch](https://chordwatch.com) is a good app and costs $24. Chordware
started as "could I build that myself" and ended up somewhere else, because two
limits in the original were worth attacking:

- **It is MIDI-only.** No keyboard, no chords. It cannot tell you what is
  happening in a recording.
- **It stops at identification.** It names what you played. It does not analyse
  function, capture progressions, suggest continuations, or expose any of it to
  other software.

So Chordware does audio as well as MIDI, and treats naming a chord as the
*start* of the job.

## What it does

- **Live chord detection** from MIDI or audio, in the notch.
- **Ranked readings, not one answer.** `A C E G` is shown as `Am7` *and*
  `C6/A` with confidences, because which one is right depends on context the
  notes alone don't carry.
- **Correct spelling.** The seventh of `Ab7` is `Gb`, never `F#`.
- **Key estimation and Roman numerals**, including secondary dominants
  (`V7/ii`), tritone substitutes (`subV7/I`), the backdoor dominant (`bVII7`),
  Neapolitans and borrowed chords — each labelled with why.
- **Cadence detection** as it happens.
- **Progression capture** with a running timeline.
- **92 scales and modes**, with the ones that fit the current chord ranked.
- **MIDI passthrough** through a virtual port named `Chordware`, off by
  default — see below.
- **A CLI** over the same engine, so all of it is scriptable.

## Requirements

macOS 14 or later, and Apple's Command Line Tools. **Xcode is not required** —
there is no `.xcodeproj`, and no third-party dependencies.

```bash
xcode-select --install    # if you don't have it
```

## Build

```bash
git clone https://github.com/YOUR_USER/chordware
cd chordware
make app        # builds dist/Chordware.app
make install    # copies it to /Applications
make run        # builds and launches
```

`make` on its own lists every target. `make test` runs the suite.

## Reading audio

Chordware listens to an audio *input*, so to analyse what your Mac is playing
you need a loopback device that turns output into input.
[BlackHole](https://github.com/ExistentialAudio/BlackHole) is free:

```bash
brew install --cask blackhole-16ch
```

Then create a Multi-Output Device in Audio MIDI Setup containing both your
speakers and BlackHole, select it as your system output, and point Chordware at
BlackHole as its input. You hear the audio and Chordware sees it.

`chordware devices` lists everything available and flags which inputs are
loopback.

macOS gates all audio input behind the microphone permission, including virtual
devices, so Chordware asks for it the first time you use audio.

### How well it works

Honestly: well on piano, pads, clean guitar and mixes with clear harmony. Less
well on dense, distorted or heavily percussive material, where the harmony is
genuinely ambiguous in the spectrum. It is a musical assistant, not a
transcription oracle. MIDI input has no such limits — it is exact.

## Getting to it

Chordware has no Dock icon. The menu bar item is the usual way in, but on a
notched MacBook with a busy menu bar the status item can end up behind the
notch where it cannot be clicked, so there is a global shortcut too:

| | |
|---|---|
| `Control-Option-Command-C` | show or hide the companion window |
| menu bar > Quit | or `Command-Q` from the menu |

## Passthrough, and why it is off

Chordware publishes a virtual MIDI source called `Chordware`. Turning on
**Send MIDI to DAW** in the menu forwards your keyboard through it, so the DAW
can take its input from Chordware.

Leave it off unless you also tell your DAW to stop listening to the keyboard
directly. Logic and most DAWs listen to *all* MIDI inputs by default, so with
passthrough on every note arrives twice — once from the keyboard, once
forwarded — and two voices a few milliseconds apart comb-filter into something
that sounds broken.

Chordware does not need passthrough to analyse anything. It listens either way.

## The CLI

```bash
chordware analyze C4 E4 G4 Bb4 D5 A5   # name a voicing
chordware analyze "Dm7 G7 Cmaj7"        # analyse a progression
chordware analyze --key Eb "Fm7 Bb7 Ebmaj7"
chordware chord C7#9                    # tones, intervals, scales that fit
chordware scales altered --root F#
chordware key "Cmaj7 Am7 Dm7 G7"
chordware devices
```

The CLI lives at `Chordware.app/Contents/Helpers/chordware`; symlink it onto
your `PATH` if you want it there.

## Architecture

```
ChordwareCore     pure Swift music theory: pitch, chords, scales, analysis.
                  No system frameworks, no I/O. Everything else depends on it.
ChordwareSignal   audio to chroma to chord, on Accelerate.
ChordwareEngine   CoreMIDI, audio input, preview synth, LiveSession.
ChordwareIsland   the notch window, its shape, geometry and state machine.
ChordwareApp      the app; the only place the engine and the island meet.
chordware         the CLI.
```

Keeping the theory in a dependency-free target is what lets the same engine back
the island, the CLI and the tests, and is why the suite runs without a window,
a keyboard or an audio device.

## Tests

```bash
make test
```

Command Line Tools ships a `Testing.framework` with its runtime library missing,
and no XCTest, so `swift test` cannot run without Xcode. Rather than keep a
second copy of the suite that only Xcode users could execute, the tests run as
an ordinary executable against a small built-in harness. The bar for running
them is the same as the bar for building the app.

The island's layout is reviewed by rendering it offscreen rather than by
screenshotting a live window:

```bash
./.build/release/ChordwareApp --render /tmp/shots
```

This needs no screen-recording permission and produces identical output on every
run, including the expansion frozen part-way open.

## Status

Working: the island, MIDI in, virtual MIDI out with passthrough, audio chord
detection, key and Roman numeral analysis, progression capture, the CLI.

Not yet: the reharmonisation and next-chord engines behind the island's `Next`
and `Reharm` tabs, MIDI export, the local HTTP API, and the settings window.

## Licence

MIT. See [LICENSE](LICENSE).
