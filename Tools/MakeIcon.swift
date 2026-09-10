#!/usr/bin/env swift
// Draws Chordware.icns from scratch. No design assets in the repo, so the icon
// is reproducible and reviewable as code like everything else.
import AppKit
import Foundation

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Chordware.icns"

/// The island silhouette, matching NotchShape: square at the top, rounded
/// below, with inverse-rounded shoulders.
func notchPath(in rect: CGRect, topRadius: CGFloat, bottomRadius: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    let t = topRadius, b = bottomRadius
    p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    p.curve(to: CGPoint(x: rect.minX + t, y: rect.maxY - t),
            controlPoint1: CGPoint(x: rect.minX + t, y: rect.maxY),
            controlPoint2: CGPoint(x: rect.minX + t, y: rect.maxY))
    p.line(to: CGPoint(x: rect.minX + t, y: rect.minY + b))
    p.curve(to: CGPoint(x: rect.minX + t + b, y: rect.minY),
            controlPoint1: CGPoint(x: rect.minX + t, y: rect.minY),
            controlPoint2: CGPoint(x: rect.minX + t, y: rect.minY))
    p.line(to: CGPoint(x: rect.maxX - t - b, y: rect.minY))
    p.curve(to: CGPoint(x: rect.maxX - t, y: rect.minY + b),
            controlPoint1: CGPoint(x: rect.maxX - t, y: rect.minY),
            controlPoint2: CGPoint(x: rect.maxX - t, y: rect.minY))
    p.line(to: CGPoint(x: rect.maxX - t, y: rect.maxY - t))
    p.curve(to: CGPoint(x: rect.maxX, y: rect.maxY),
            controlPoint1: CGPoint(x: rect.maxX - t, y: rect.maxY),
            controlPoint2: CGPoint(x: rect.maxX - t, y: rect.maxY))
    p.close()
    return p
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = size

    // macOS icon geometry: content inset, superellipse-ish corner.
    let inset = s * 0.06
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let corner = body.width * 0.2237

    let backdrop = NSBezierPath(roundedRect: body, xRadius: corner, yRadius: corner)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.17, alpha: 1),
        NSColor(calibratedRed: 0.04, green: 0.04, blue: 0.06, alpha: 1),
    ])?.draw(in: backdrop, angle: -90)

    // The island, hanging from the top of the icon body.
    let islandWidth = body.width * 0.62
    let islandHeight = body.height * 0.30
    let island = CGRect(x: body.midX - islandWidth / 2,
                        y: body.maxY - islandHeight,
                        width: islandWidth, height: islandHeight)
    NSColor.black.setFill()
    notchPath(in: island, topRadius: s * 0.035, bottomRadius: s * 0.055).fill()

    // A triad, stacked in thirds, as three rungs below the island.
    let rungWidth = body.width * 0.46
    let rungHeight = s * 0.055
    let gap = s * 0.052
    let accents = [
        NSColor(calibratedRed: 0.42, green: 0.78, blue: 1.00, alpha: 1),
        NSColor(calibratedRed: 0.55, green: 0.85, blue: 0.72, alpha: 1),
        NSColor(calibratedRed: 1.00, green: 0.78, blue: 0.42, alpha: 1),
    ]
    // Offset each rung a little, so it reads as a voicing rather than a menu.
    let offsets: [CGFloat] = [-0.10, 0.06, -0.02]
    for (index, colour) in accents.enumerated() {
        let y = island.minY - gap * 1.5 - CGFloat(index) * (rungHeight + gap)
        let x = body.midX - rungWidth / 2 + offsets[index] * rungWidth
        let rung = CGRect(x: x, y: y - rungHeight, width: rungWidth, height: rungHeight)
        colour.setFill()
        NSBezierPath(roundedRect: rung, xRadius: rungHeight / 2, yRadius: rungHeight / 2).fill()
    }

    image.unlockFocus()
    return image
}

let iconset = URL(fileURLWithPath: output).deletingPathExtension().appendingPathExtension("iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                              (256, 1), (256, 2), (512, 1), (512, 2)]
for (point, scale) in variants {
    let pixels = point * scale
    let image = drawIcon(size: CGFloat(pixels))
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    let name = scale == 1 ? "icon_\(point)x\(point).png" : "icon_\(point)x\(point)@2x.png"
    try png.write(to: iconset.appendingPathComponent(name))
}

let convert = Process()
convert.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
convert.arguments = ["-c", "icns", iconset.path, "-o", output]
try convert.run()
convert.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print("  wrote \(output)")
