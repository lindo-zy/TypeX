import AppKit

// mock preview of the new settings header, dark (top) + light (bottom)
let w = CGFloat(560), h = CGFloat(500)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 560, pixelsHigh: 500,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: w, height: h)
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx

func drawHeader(dark: Bool, top: CGFloat) {
    let rect = NSRect(x: 0, y: top, width: w, height: 250)
    (dark ? NSColor(calibratedWhite: 0.12, alpha: 1) : NSColor(calibratedWhite: 0.95, alpha: 1)).setFill()
    rect.fill()
    let iconSize: CGFloat = 120
    let iconRect = NSRect(x: w / 2 - iconSize / 2, y: rect.maxY - 28 - iconSize, width: iconSize, height: iconSize)
    guard let icon = NSImage(contentsOfFile: "typexprefs/Resources/TypeX512.png") else { exit(1) }
    let rounded = NSBezierPath(roundedRect: iconRect, xRadius: iconSize * 0.225, yRadius: iconSize * 0.225)
    // shadow (cast from the rounded square)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 12
    shadow.shadowOffset = NSSize(width: 0, height: 6)
    shadow.set()
    NSColor.black.setFill()
    rounded.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    // rounded clip + icon
    NSGraphicsContext.current?.saveGraphicsState()
    rounded.setClip()
    icon.draw(in: iconRect)
    NSGraphicsContext.current?.restoreGraphicsState()

    let title = NSAttributedString(string: "TypeX", attributes: [
        .font: NSFont.systemFont(ofSize: 36, weight: .bold),
        .foregroundColor: dark ? NSColor.white.withAlphaComponent(0.92) : NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 1),
    ])
    title.draw(at: NSPoint(x: w / 2 - title.size().width / 2, y: iconRect.minY - 14 - 42))
}
drawHeader(dark: true, top: 250)
drawHeader(dark: false, top: 0)
NSGraphicsContext.restoreGraphicsState()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "icons/header-preview.png"))
print("wrote icons/header-preview.png")
