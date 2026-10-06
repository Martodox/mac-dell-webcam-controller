// Generates DellCamera.icns: a System Settings–style rounded square with the
// "web.camera" SF Symbol. Usage: swift Tools/make-icon.swift <output.icns>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "DellCamera.icns")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("DellCamera.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let size = CGFloat(pixels)
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let tile = NSBezierPath(roundedRect: rect, xRadius: size * 0.225, yRadius: size * 0.225)
    NSGradient(starting: NSColor(srgbRed: 0.36, green: 0.40, blue: 0.47, alpha: 1),
               ending: NSColor(srgbRed: 0.13, green: 0.15, blue: 0.19, alpha: 1))!
        .draw(in: tile, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "web.camera", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let s = symbol.size
        symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try render(points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()
exit(task.terminationStatus)
