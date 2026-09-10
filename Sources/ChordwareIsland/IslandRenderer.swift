import AppKit
import SwiftUI

/// Renders island states to PNG without putting anything on screen.
///
/// This is how the island's layout is checked: `ImageRenderer` walks the same
/// SwiftUI hierarchy the window shows, so the output is faithful, needs no
/// screen-recording permission, and is identical on every run — which a
/// screenshot of a live animating window is not.
@MainActor
public enum IslandRenderer {
    public static let states: [(name: String, state: IslandState)] = [
        ("glance", .glance),
        ("expanded", .expanded),
        ("act-next", .act),
        ("toast", .toast(IslandToast(kind: .cadence,
                                     title: "authentic (V\u{2013}I)",
                                     detail: "G7 \u{2192} Cmaj7"))),
        // The longest label the toast can carry. This one used to run past the
        // island's edge, so it stays as a fixture.
        ("toast-long", .toast(IslandToast(kind: .cadence,
                                          title: "backdoor (bVII7\u{2013}I)",
                                          detail: "Bb7 \u{2192} Cmaj13"))),
    ]

    /// Render every state, plus the non-notched fallback, into `directory`.
    public static func renderAll(to directory: URL, geometry: ScreenGeometry) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []

        for (name, state) in states {
            let model = IslandPreviewData.model(state: state)
            if case .act = state { model.tab = .suggest }
            if let url = try render(model: model, geometry: geometry,
                                    to: directory.appendingPathComponent("island-\(name).png")) {
                written.append(url)
            }
        }

        // The other three tabs of the interactive state.
        for tab in [IslandTab.reharm, .progression, .scales] {
            let model = IslandPreviewData.model(state: .act)
            model.tab = tab
            let name = "island-act-\(tab.rawValue.lowercased()).png"
            if let url = try render(model: model, geometry: geometry,
                                    to: directory.appendingPathComponent(name)) {
                written.append(url)
            }
        }

        // The pill fallback, as an external display would show it.
        let virtual = ScreenGeometry(notchWidth: ScreenGeometry.virtualNotchSize.width,
                                     notchHeight: ScreenGeometry.virtualNotchSize.height,
                                     isPhysical: false,
                                     screenFrame: geometry.screenFrame)
        for (name, state) in [("glance", IslandState.glance), ("expanded", .expanded)] {
            let model = IslandPreviewData.model(state: state)
            if let url = try render(model: model, geometry: virtual,
                                    to: directory.appendingPathComponent("pill-\(name).png")) {
                written.append(url)
            }
        }
        written += try renderReveal(to: directory, geometry: geometry)
        if let url = try renderCompanion(to: directory.appendingPathComponent("companion.png")) {
            written.append(url)
        }
        if let url = try renderCompanion(to: directory.appendingPathComponent("companion-idle.png"),
                                         sounding: false) {
            written.append(url)
        }
        // One key and two keys are not chords, but must still read out.
        if let url = try renderCompanion(to: directory.appendingPathComponent("companion-single.png"),
                                         notes: [62]) {
            written.append(url)
        }
        if let url = try renderCompanion(to: directory.appendingPathComponent("companion-dyad.png"),
                                         notes: [60, 67]) {
            written.append(url)
        }
        return written
    }

    /// Render the companion window's contents at its default size.
    public static func renderCompanion(to url: URL, sounding: Bool = true,
                                       notes: [Int]? = nil) throws -> URL? {
        let model = IslandPreviewData.model(state: .glance)
        model.isSounding = sounding
        if !sounding { model.heldNotes = [] }
        if let notes {
            model.presentNotesOnly(notes, atMs: 0)
        }
        let view = CompanionView(model: model).frame(width: 900, height: 600)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        try png.write(to: url)
        return url
    }

    /// Render the expansion part-way open, to show that the panel is revealed
    /// by a growing clip rather than faded in.
    public static func renderReveal(to directory: URL, geometry: ScreenGeometry) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []
        let full = IslandRootView.expandedDetailHeight
        for (label, fraction) in [("00", 0.0), ("35", 0.35), ("70", 0.70), ("100", 1.0)] {
            let model = IslandPreviewData.model(state: .expanded)
            let url = directory.appendingPathComponent("reveal-\(label).png")
            if let out = try render(model: model, geometry: geometry, to: url,
                                    detailHeightOverride: full * fraction) {
                written.append(out)
            }
        }
        return written
    }

    public static func render(model: IslandModel, geometry: ScreenGeometry, to url: URL,
                              detailHeightOverride: CGFloat? = nil) throws -> URL? {
        var size = IslandRootView.size(for: model.state, geometry: geometry)
        if let detailHeightOverride {
            size.height = geometry.notchHeight + detailHeightOverride
        }
        let margin: CGFloat = 40
        let canvas = CGSize(width: size.width + margin * 2, height: size.height + margin)

        let content = ZStack(alignment: .top) {
            // Stand-in for the desktop, so the black island is visible and the
            // top edge reads as the screen bezel.
            LinearGradient(colors: [Color(white: 0.30), Color(white: 0.16)],
                           startPoint: .top, endPoint: .bottom)
            IslandRootView(model: model, geometry: geometry,
                           detailHeightOverride: detailHeightOverride)
        }
        .frame(width: canvas.width, height: canvas.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        try png.write(to: url)
        return url
    }
}
