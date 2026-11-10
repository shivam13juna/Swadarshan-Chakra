// Package the owner's artwork in a native icon tile with a narrow inner margin.
import AppKit

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: generate-icon.swift <source.png> <output.iconset>\n", stderr)
    exit(1)
}
let source = URL(fileURLWithPath: CommandLine.arguments[1])
guard let artwork = NSImage(contentsOf: source), artwork.isValid,
      artwork.size.width > 0, artwork.size.height > 0 else {
    fputs("Cannot load app icon: \(source.path)\n", stderr)
    exit(1)
}
let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func render(size: Int, name: String) throws {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Could not create icon canvas") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }
    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    context.cgContext.clear(canvas)
    context.imageInterpolation = .high
    // Give macOS an already-composed icon body, so it doesn't shrink the circular
    // artwork into an automatically added white tile. The source PNG stays intact.
    // The 100/1024 outer margin is the standard macOS icon canvas safe area.
    let tile = canvas.insetBy(dx: CGFloat(size) * 100 / 1024, dy: CGFloat(size) * 100 / 1024)
    NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
    NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.22, yRadius: tile.height * 0.22).fill()
    let artworkArea = tile.insetBy(dx: tile.width * 0.025, dy: tile.height * 0.025)
    let scale = min(artworkArea.width / artwork.size.width, artworkArea.height / artwork.size.height)
    let width = artwork.size.width * scale
    let height = artwork.size.height * scale
    let destination = NSRect(x: (CGFloat(size) - width) / 2, y: (CGFloat(size) - height) / 2,
                             width: width, height: height)
    artwork.draw(in: destination, from: .zero, operation: .sourceOver, fraction: 1)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not render icon") }
    try png.write(to: directory.appendingPathComponent(name))
}

for size in [16, 32, 128, 256, 512] {
    try render(size: size, name: "icon_\(size)x\(size).png")
    try render(size: size * 2, name: "icon_\(size)x\(size)@2x.png")
}
