import AppKit
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = root.appendingPathComponent("MTPExplorer/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let canvas = NSImage(size: NSSize(width: 1024, height: 1024))
canvas.lockFocus()
let base = NSBezierPath(roundedRect: NSRect(x: 75, y: 75, width: 874, height: 874), xRadius: 190, yRadius: 190)
NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.64, blue: 0.99, alpha: 1), ending: NSColor(calibratedRed: 0.03, green: 0.30, blue: 0.83, alpha: 1))!.draw(in: base, angle: -90)
let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.18); shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width: 0, height: -12)
NSGraphicsContext.saveGraphicsState(); shadow.set()
let folder = NSBezierPath()
folder.move(to: NSPoint(x: 200, y: 320)); folder.line(to: NSPoint(x: 200, y: 680))
folder.curve(to: NSPoint(x: 235, y: 715), controlPoint1: NSPoint(x: 200, y: 703), controlPoint2: NSPoint(x: 213, y: 715))
folder.line(to: NSPoint(x: 420, y: 715)); folder.line(to: NSPoint(x: 470, y: 660)); folder.line(to: NSPoint(x: 790, y: 660))
folder.curve(to: NSPoint(x: 825, y: 625), controlPoint1: NSPoint(x: 812, y: 660), controlPoint2: NSPoint(x: 825, y: 648))
folder.line(to: NSPoint(x: 825, y: 320)); folder.close()
NSColor(calibratedRed: 0.51, green: 0.82, blue: 1, alpha: 1).setFill(); folder.fill()
let front = NSBezierPath(roundedRect: NSRect(x: 180, y: 285, width: 665, height: 340), xRadius: 38, yRadius: 38)
NSGradient(starting: NSColor(calibratedRed: 0.84, green: 0.96, blue: 1, alpha: 1), ending: NSColor(calibratedRed: 0.50, green: 0.82, blue: 1, alpha: 1))!.draw(in: front, angle: -90)
NSGraphicsContext.restoreGraphicsState()
let phone = NSBezierPath(roundedRect: NSRect(x: 412, y: 345, width: 200, height: 330), xRadius: 33, yRadius: 33)
NSColor(calibratedRed: 0.03, green: 0.32, blue: 0.67, alpha: 1).setFill(); phone.fill()
let screen = NSBezierPath(roundedRect: NSRect(x: 426, y: 360, width: 172, height: 300), xRadius: 22, yRadius: 22)
NSColor.white.setFill(); screen.fill()
let notch = NSBezierPath(roundedRect: NSRect(x: 476, y: 638, width: 72, height: 13), xRadius: 6, yRadius: 6)
NSColor(calibratedRed: 0.03, green: 0.32, blue: 0.67, alpha: 1).setFill(); notch.fill()
let arrows = NSBezierPath(); arrows.lineWidth = 14; arrows.lineCapStyle = .round; arrows.lineJoinStyle = .round
arrows.move(to: NSPoint(x: 462, y: 536)); arrows.line(to: NSPoint(x: 558, y: 536)); arrows.line(to: NSPoint(x: 537, y: 557))
arrows.move(to: NSPoint(x: 558, y: 536)); arrows.line(to: NSPoint(x: 537, y: 515))
arrows.move(to: NSPoint(x: 558, y: 465)); arrows.line(to: NSPoint(x: 462, y: 465)); arrows.line(to: NSPoint(x: 483, y: 486))
arrows.move(to: NSPoint(x: 462, y: 465)); arrows.line(to: NSPoint(x: 483, y: 444))
NSColor.systemBlue.setStroke(); arrows.stroke()
canvas.unlockFocus()
var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        canvas.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels)); NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)@\(scale)x.png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
    }
}
let data = try JSONSerialization.data(withJSONObject: ["images": images, "info": ["version": 1, "author": "xcode"]], options: [.prettyPrinted, .sortedKeys])
try data.write(to: destination.appendingPathComponent("Contents.json"))
try "{\"info\":{\"author\":\"xcode\",\"version\":1}}".write(to: root.appendingPathComponent("MTPExplorer/Resources/Assets.xcassets/Contents.json"), atomically: true, encoding: .utf8)
