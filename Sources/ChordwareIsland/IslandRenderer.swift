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
public enum IslandRenderer {
    /// Write every case worth looking at into `directory`.
    public static func renderAll(to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []

        func shot(_ name: String, _ make: (URL) throws -> URL?) rethrows {
            if let url = try make(directory.appendingPathComponent(name + ".png")) {
                written.append(url)
            }
        }

        try shot("companion") { try renderCompanion(to: $0) }
        try shot("companion-idle") { try renderCompanion(to: $0, sounding: false) }
        // Nothing played yet: its own state, and the first thing anyone sees.
        try shot("companion-empty") { try renderCompanion(to: $0, sounding: false, notes: []) }
        // One key and two keys are not chords, but must still read out.
        try shot("companion-single") { try renderCompanion(to: $0, notes: [62]) }
        try shot("companion-dyad") { try renderCompanion(to: $0, notes: [60, 67]) }
        // A plain triad, which is what most of the colour work has to answer to.
        try shot("companion-triad") { try renderCompanion(to: $0, notes: [62, 65, 69]) }

        // Every height the window can be dragged to, from the smallest the
        // layout allows upward.
        for height in [640, 500, 400, 300] as [CGFloat] {
            try shot("companion-h\(Int(height))") {
                try renderCompanion(to: $0, size: CGSize(width: 900, height: height))
            }
        }
        // Narrow, where the keys are at their smallest and the labels drop out.
        try shot("companion-narrow") {
            try renderCompanion(to: $0, size: CGSize(width: 560, height: 300))
        }
        return written
    }

    /// Render the window's contents at its default size.
    public static func renderCompanion(to url: URL, sounding: Bool = true,
                                       notes: [Int]? = nil,
                                       size: CGSize = CGSize(width: 900, height: 400)) throws -> URL? {
        let model = IslandPreviewData.model()
        model.isSounding = sounding
        if !sounding { model.heldNotes = [] }
        if let notes {
            if notes.count >= 3 {
                model.present(candidates: ChordDetector.detect(midiNotes: notes),
                              heldNotes: notes, atMs: 0)
            } else {
                model.presentNotesOnly(notes, atMs: 0)
            }
        }
        // Clip like a window does: ImageRenderer otherwise sizes to the
        // content's real layout, so overflow escapes the frame and the
        // render stops resembling what is on screen.
        let view = CompanionView(model: model)
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
