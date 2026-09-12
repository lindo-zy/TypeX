import AppKit

// usage: swift render_icon.swift <svg> <size:out.png> [size:out.png ...]
let args = CommandLine.arguments
guard args.count >= 3, let img = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write("failed to load svg".data(using: .utf8)!)
    exit(1)
}
for spec in args.dropFirst(2) {
    let parts = spec.split(separator: ":", maxSplits: 1)
    let size = Int(parts[0])!
    let out = String(parts[1])
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    img.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
    print("wrote \(out) \(size)x\(size)")
}
