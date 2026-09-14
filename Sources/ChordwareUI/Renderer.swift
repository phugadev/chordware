import AppKit
import ChordwareCore
import SwiftUI

/// Renders the window to PNG without putting anything on screen.
///
/// This is how the layout is checked: `ImageRenderer` walks the same SwiftUI
/// hierarchy the window shows, so the output is faithful, needs no
/// screen-recording permission, and is identical on every run — which a
/// screenshot of a live animating window is not.
@MainActor
public enum Renderer {
    /// Write every case worth looking at into `directory`.
    public static func renderAll(to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []

        func shot(_ name: String, _ make: (URL) throws -> URL?) rethrows {
            if let url = try make(directory.appendingPathComponent(name + ".png")) {
                written.append(url)
            }
        }

        try shot("window") { try render(to: $0) }
        try shot("window-idle") { try render(to: $0, sounding: false) }
        // Nothing played yet: its own state, and the first thing anyone sees.
        try shot("window-empty") { try render(to: $0, sounding: false, notes: []) }
        // One key and two keys are not chords, but must still read out.
        try shot("window-single") { try render(to: $0, notes: [62]) }
        // A single black key: the chord line and the caption under it have to
        // agree about Bb versus A#, and they did not.
        try shot("window-single-black") { try render(to: $0, notes: [58]) }
        try shot("window-dyad") { try render(to: $0, notes: [60, 67]) }
        // A plain triad, which is what most of the colour work has to answer to.
        try shot("window-triad") { try render(to: $0, notes: [62, 65, 69]) }

        // Every height the window can be dragged to, from the smallest the
        // layout allows upward.
        for height in [400, 320, 272, 212] as [CGFloat] {
            try shot("window-h\(Int(height))") {
                try render(to: $0, size: CGSize(width: 900, height: height))
            }
        }
        // TRIAL: a chord clicked out of the history. Its keys light up and the
        // readout names it, until you play again.
        try shot("trial-inspecting") { try render(to: $0, inspectIndex: 3) }
        // The palettes, side by side, on the voicing that tests them: three
        // white keys and one black, where the black one is the note you most
        // need to see.
        for (name, palette) in [("orchid", Theme.orchid),
                                ("emerald", Theme.emerald),
                                ("indigo", Theme.indigo),
                                ("coral", Theme.coral)] {
            try shot("palette-\(name)") {
                try render(to: $0, notes: [62, 65, 69, 70], palette: palette)
            }
        }
        // Narrow, where the keys are at their smallest and the labels drop out.
        try shot("window-narrow") {
            try render(to: $0, size: CGSize(width: 520, height: 212))
        }
        return written
    }

    /// Render the window's contents at its default size.
    public static func render(to url: URL, sounding: Bool = true,
                                       notes: [Int]? = nil,
                                       palette: Theme.Palette = Theme.standard,
                                       inspectIndex: Int? = nil,

                                       size: CGSize = CGSize(width: 900, height: 272)) throws -> URL? {
        let model = PreviewData.model()
        model.isSounding = sounding
        // Hands off the keys: the readout empties, so this is the same picture
        // as nothing having been played. Kept as its own fixture because it is
        // reached by a different route.
        if !sounding { model.clearNotes(atMs: 0) }
        if let notes {
            if notes.count >= 3 {
                model.present(candidates: ChordDetector.detect(midiNotes: notes),
                              heldNotes: notes, atMs: 0)
            } else {
                model.presentNotesOnly(notes, atMs: 0)
            }
        }
        if let inspectIndex, inspectIndex < model.progression.events.count {
            model.inspect(model.progression.events[inspectIndex])
        }
        // Clip like a window does: ImageRenderer otherwise sizes to the
        // content's real layout, so overflow escapes the frame and the
        // render stops resembling what is on screen.
        let view = ChordwareView(model: model, palette: palette)
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipped()
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        try png.write(to: url)
        return url
    }
}
