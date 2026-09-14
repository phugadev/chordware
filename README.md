# Chordware

A virtual piano keyboard that tells you what you are playing.

Play, and the window shows it: the chord in amber on black, the keys under your
fingers lit and named with their octave, and the last few chords along the foot.
Lift your hands and the chord goes back to black; the history stays. Your MIDI
device is in the title bar. That is the whole window. Put it
on a second screen while you practise, or beside your hands while you record. It reads your MIDI keyboard.

Free, MIT-licensed, no accounts, no telemetry, nothing leaves your machine.

## Why

[Chordwatch](https://chordwatch.com) is a good app and costs $24. Chordware
started as "could I build that myself" and ended up somewhere else, because two
limits in the original were worth attacking:

- **It stops at identification.** It names what you played. It does not analyse
  function, capture progressions, suggest continuations, or expose any of it to
  other software.

Chordware listens to MIDI too. Audio chord detection was built, measured
against recorded piano, electric piano and guitar at 22 of 24 chords, and then
removed: it needs a loopback driver and a routing decision before it can hear
anything, which is a setup chore in front of a tool whose whole point is that
you sit down and play. The commit is in the history if it is ever worth
reviving.

## What it does

In the window:

- **Live chord detection** from MIDI, on a keyboard you can watch.
- **Three colours, no legend.** Amber for the chord, green for white keys under
  your fingers, violet for black ones. Colouring each key by its function in the
  chord was tried, and it asks you to learn a legend before the display tells
  you anything.
- **Correct spelling.** The seventh of `Ab7` is `Gb`, never `F#`. Chordware
  tracks the key to get this right; it does not put the key on screen. With no
  key established yet, ties break towards flats — `F#3 C#4 G#4` is `Gbsus2`,
  because in the keys people play in, the black notes are flats.
- **Capture.** Everything you play is recorded from launch, saveable as a `.mid`
  at any point, so an idea found by accident is not lost.
- **A history strip** of the last few chords, along the foot. Click one and it
  goes up on the keyboard, with the notes you actually played; play anything and
  it lets go.
- **MIDI passthrough** through a virtual port named `Chordware`, off by
  default — see below.

Behind it, in `ChordwareCore` and the CLI:

- **Ranked readings, not one answer.** `A C E G` is `Am7` *and* `C6/A` with
  confidences, because which one is right depends on context the notes alone
  don't carry.
- **Key estimation and Roman numerals**, including secondary dominants
  (`V7/ii`), tritone substitutes (`subV7/I`), the backdoor dominant (`bVII7`),
  Neapolitans and borrowed chords — each labelled with why.
- **Cadence detection**, progression capture, and **92 scales and modes** with
  the ones that fit a chord ranked.

The window used to show all of it. It was true and it went unread: when your
hands are on the keys, you look at one thing.

## Requirements

macOS 14 or later, and Apple's Command Line Tools. **Xcode is not required** —
there is no `.xcodeproj`, and no third-party dependencies.

```bash
xcode-select --install    # if you don't have it
```

## Build

```bash
git clone https://github.com/phugadev/chordware
cd chordware
make app        # builds dist/Chordware.app
make install    # copies it to /Applications
make run        # builds and launches
```

`make` on its own lists every target. `make test` runs the suite.

### How well it works

Honestly: well on piano, pads, clean guitar and mixes with clear harmony. Less
well on dense, distorted or heavily percussive material, where the harmony is
genuinely ambiguous in the spectrum. It is a musical assistant, not a
transcription oracle. MIDI input has no such limits — it is exact.

## Two ways to show it

| Mode | What it is |
|---|---|
| **Companion** | Everything: keyboard, notes and intervals, alternative readings, fitting scales, the progression so far. |
| **Presentation** | The keyboard and one line of text, in a window shrunk to fit. For recording, or playing to a room. |

Both draw the same keyboard at the same key size. They differ in what surrounds
it and how big the window is, never in how the instrument is drawn.

`Control-Option-Command-P` switches between them.

## Saving what you played

Chordware records every note you play, from launch, without being asked. There
is no record button, deliberately: the case this exists for is finding
something good *without meaning to* — sitting at the keyboard with no DAW open
— and a button you have to press first is exactly the one you will not have
pressed.

**menu bar > Save Performance as MIDI…** writes it as a standard `.mid` file
that any DAW will open, with the note count shown so you know there is
something there. **Clear Performance** starts over. The buffer is bounded, so
leaving Chordware running all day is safe.

This does not try to replace your DAW's recording. It is for the times the DAW
is not open.

## Spelling, and the key

Nothing about accidentals is hardcoded. A note is spelled by the chord it
belongs to first, and by the key signature second — which is why the same black
key reads `B♭` inside a C7 and `A♯` inside an F♯7, and why an unaccompanied
black key reads `G♭` in F major and `F♯` in C major. That is how notation works
rather than a shortcut.

The consequence is that the key has to be established before spelling settles,
and detecting it takes a few chords. If you already know what you are in, name
it: **menu bar > Key**. Everything then spells against it from the first note,
and the readout shows a padlock so a fixed key is never mistaken for a detector
that has stopped responding.

## The keyboard

The keyboard is an instrument and the window is a view onto it. Keys have fixed
proportions and never stretch to fill a window; instead the visible range slides
to follow what you play. Pressing octave-up on a controller changes *which*
notes are shown, not how many.

The range is learned per device and remembered. It widens only for a reach that
genuinely does not fit, and re-centres when you pause — never mid-chord, because
moving the keys while you are looking at them is worse than showing the wrong
range.

## Getting to it

Chordware has no Dock icon. The menu bar item is the usual way in, but on a
notched MacBook with a busy menu bar the status item can end up behind the
notch where it cannot be clicked, so there is a global shortcut too:

| | |
|---|---|
| `Control-Option-Command-C` | show or hide the window |
| `Control-Option-Command-T` | keep the window above everything |
| `Control-Option-Command-K` | panic: release every note, clear every lit key |
| `Command-S` (menu open) | save the performance as MIDI |
| menu bar > Quit | or `Command-Q` from the menu |

These are system-wide and work whether or not you can see the status item. They
use Carbon's `RegisterEventHotKey` rather than a keystroke monitor, so Chordware
never asks for permission to watch what you type; if another app already owns
one of them, Chordware says so on stderr at launch rather than failing quietly.

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
ChordwareEngine   CoreMIDI in and out, the preview synth, LiveSession.
ChordwareUI       the window: the keyboard, the chord name and the menu bar item.
ChordwareApp      the app; the only place the engine and the view meet.
chordware         the CLI.
```

Keeping the theory in a dependency-free target is what lets the same engine back
the window, the CLI and the tests, and is why the suite runs without a window,
a keyboard attached.

## Tests

```bash
make test
```

Command Line Tools ships a `Testing.framework` with its runtime library missing,
and no XCTest, so `swift test` cannot run without Xcode. Rather than keep a
second copy of the suite that only Xcode users could execute, the tests run as
an ordinary executable against a small built-in harness. The bar for running
them is the same as the bar for building the app.

The layout is reviewed by rendering it offscreen rather than by screenshotting
a live window:

```bash
./.build/release/ChordwareApp --render /tmp/shots
```

This needs no screen-recording permission and produces identical output on every
run, at every window height the layout has to survive.

## Status

Working: the window, MIDI in, virtual MIDI out with passthrough, performance
capture, and the CLI over the full engine.

Not yet: the local HTTP API. Suggestion and reharmonisation are deliberately out
of scope — they serve composing rather than seeing what you play.

Gone: the notch overlay. It hung above the menu bar on the built-in screen, at a
level above every other window, and its footprint swallowed clicks across the
top of the display. It was also the wrong place for this: you cannot watch a
keyboard that is above the screen you are looking at.

## Licence

MIT. See [LICENSE](LICENSE).
