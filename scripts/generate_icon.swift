import AppKit

// The same vector drawing supplies the application icon and transparent logo.
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.iconset", isDirectory: true)
let logoURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst(2).first ?? outputDirectory.deletingLastPathComponent().appendingPathComponent("Cornucopia.png").path)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func rotated(at point: NSPoint, degrees: CGFloat, draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    var transform = AffineTransform(translationByX: point.x, byY: point.y)
    transform.rotate(byDegrees: degrees)
    (transform as NSAffineTransform).concat()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

func leaf(from origin: NSPoint, to tip: NSPoint, fill: NSColor, breadth: CGFloat) {
    let dx = tip.x - origin.x, dy = tip.y - origin.y
    let length = hypot(dx, dy)
    let nx = -dy / length * breadth, ny = dx / length * breadth
    let middle = NSPoint(x: origin.x + dx * 0.57, y: origin.y + dy * 0.57)
    let path = NSBezierPath()
    path.move(to: origin)
    path.curve(to: tip, controlPoint1: NSPoint(x: middle.x + nx, y: middle.y + ny), controlPoint2: NSPoint(x: tip.x + nx * 0.30, y: tip.y + ny * 0.30))
    path.curve(to: origin, controlPoint1: NSPoint(x: tip.x - nx * 0.55, y: tip.y - ny * 0.55), controlPoint2: NSPoint(x: middle.x - nx, y: middle.y - ny))
    path.close()
    fill.setFill()
    path.fill()
    let vein = NSBezierPath()
    vein.move(to: origin)
    vein.line(to: NSPoint(x: tip.x - dx * 0.16, y: tip.y - dy * 0.16))
    vein.lineWidth = 3.5
    vein.lineCapStyle = .round
    color(0xF4F8F7, alpha: 0.25).setStroke()
    vein.stroke()
}

func oval(_ rect: NSRect, colors: [NSColor]) {
    NSGradient(colors: colors)!.draw(in: NSBezierPath(ovalIn: rect), angle: -50)
}

func stem(from start: NSPoint, to end: NSPoint, width: CGFloat = 9) {
    let path = NSBezierPath()
    path.move(to: start)
    path.curve(to: end, controlPoint1: NSPoint(x: start.x - 12, y: start.y + 20), controlPoint2: NSPoint(x: end.x + 10, y: end.y - 10))
    path.lineWidth = width
    path.lineCapStyle = .round
    color(0x526B4E).setStroke()
    path.stroke()
}

func cornucopia() {
    leaf(from: NSPoint(x: 620, y: 590), to: NSPoint(x: 691, y: 808), fill: color(0x8EBDA3), breadth: 46)
    leaf(from: NSPoint(x: 654, y: 617), to: NSPoint(x: 836, y: 757), fill: color(0x147D76), breadth: 49)
    leaf(from: NSPoint(x: 677, y: 556), to: NSPoint(x: 874, y: 593), fill: color(0x7FAF97), breadth: 39)

    let horn = NSBezierPath()
    horn.move(to: NSPoint(x: 200, y: 393))
    horn.curve(to: NSPoint(x: 462, y: 306), controlPoint1: NSPoint(x: 252, y: 276), controlPoint2: NSPoint(x: 349, y: 274))
    horn.curve(to: NSPoint(x: 699, y: 474), controlPoint1: NSPoint(x: 588, y: 332), controlPoint2: NSPoint(x: 676, y: 395))
    horn.curve(to: NSPoint(x: 552, y: 670), controlPoint1: NSPoint(x: 732, y: 568), controlPoint2: NSPoint(x: 625, y: 718))
    horn.curve(to: NSPoint(x: 425, y: 456), controlPoint1: NSPoint(x: 541, y: 591), controlPoint2: NSPoint(x: 478, y: 507))
    horn.curve(to: NSPoint(x: 200, y: 393), controlPoint1: NSPoint(x: 341, y: 376), controlPoint2: NSPoint(x: 249, y: 361))
    horn.close()

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x0B252B, alpha: 0.16)
    shadow.shadowOffset = NSSize(width: 0, height: -13)
    shadow.shadowBlurRadius = 19
    shadow.set()
    NSGradient(colors: [color(0xB78A4D), color(0xD9B574), color(0xEAD098)])!.draw(in: horn, angle: 55)
    NSGraphicsContext.restoreGraphicsState()

    // Fine basket fibers follow the horn's curvature.
    NSGraphicsContext.saveGraphicsState()
    horn.addClip()
    for index in 0..<14 {
        let step = CGFloat(index)
        let fiber = NSBezierPath()
        fiber.move(to: NSPoint(x: 188, y: 389 - step * 5))
        fiber.curve(to: NSPoint(x: 599 + step * 9, y: 690 - step * 13), controlPoint1: NSPoint(x: 352, y: 280 - step * 4), controlPoint2: NSPoint(x: 538 + step * 6, y: 379 - step * 2))
        fiber.lineWidth = 2.5
        color(0x8C693D, alpha: 0.20).setStroke()
        fiber.stroke()
    }
    for index in 0..<8 {
        let step = CGFloat(index)
        let rib = NSBezierPath()
        rib.move(to: NSPoint(x: 287 + step * 45, y: 233 + step * 26))
        rib.curve(to: NSPoint(x: 306 + step * 36, y: 412 + step * 43), controlPoint1: NSPoint(x: 366 + step * 48, y: 270 + step * 25), controlPoint2: NSPoint(x: 347 + step * 42, y: 364 + step * 28))
        rib.lineWidth = 4.5
        color(0xF5DEAD, alpha: 0.50).setStroke()
        rib.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()

    rotated(at: NSPoint(x: 627, y: 575), degrees: 37) {
        oval(NSRect(x: -90, y: -139, width: 180, height: 278), colors: [color(0xECD098), color(0xBB8C4C)])
        oval(NSRect(x: -65, y: -115, width: 130, height: 230), colors: [color(0x664B2E), color(0x9A7745)])
    }

    let pear = NSBezierPath()
    pear.move(to: NSPoint(x: 747, y: 770))
    pear.curve(to: NSPoint(x: 700, y: 695), controlPoint1: NSPoint(x: 711, y: 770), controlPoint2: NSPoint(x: 735, y: 737))
    pear.curve(to: NSPoint(x: 691, y: 618), controlPoint1: NSPoint(x: 660, y: 659), controlPoint2: NSPoint(x: 665, y: 625))
    pear.curve(to: NSPoint(x: 808, y: 620), controlPoint1: NSPoint(x: 721, y: 587), controlPoint2: NSPoint(x: 778, y: 590))
    pear.curve(to: NSPoint(x: 783, y: 704), controlPoint1: NSPoint(x: 840, y: 656), controlPoint2: NSPoint(x: 805, y: 683))
    pear.curve(to: NSPoint(x: 747, y: 770), controlPoint1: NSPoint(x: 758, y: 731), controlPoint2: NSPoint(x: 782, y: 772))
    pear.close()
    NSGradient(colors: [color(0xD3DDA2), color(0x9ABB81)])!.draw(in: pear, angle: -30)
    stem(from: NSPoint(x: 749, y: 764), to: NSPoint(x: 758, y: 797))
    leaf(from: NSPoint(x: 753, y: 776), to: NSPoint(x: 804, y: 806), fill: color(0x4E957A), breadth: 18)

    let grapeCenters: [NSPoint] = [NSPoint(x: 630, y: 723), NSPoint(x: 677, y: 716), NSPoint(x: 601, y: 681), NSPoint(x: 650, y: 674), NSPoint(x: 697, y: 667), NSPoint(x: 625, y: 630), NSPoint(x: 671, y: 623), NSPoint(x: 651, y: 579)]
    for (index, point) in grapeCenters.enumerated() {
        oval(NSRect(x: point.x - 27, y: point.y - 27, width: 55, height: 55), colors: [color(index.isMultiple(of: 2) ? 0xBDA3CC : 0xB397C3), color(0x9071A5)])
        color(0xF4F8F7, alpha: 0.27).setFill()
        NSBezierPath(ovalIn: NSRect(x: point.x - 12, y: point.y + 8, width: 11, height: 8)).fill()
    }
    stem(from: NSPoint(x: 649, y: 744), to: NSPoint(x: 641, y: 774), width: 7)

    let apple = NSBezierPath()
    apple.move(to: NSPoint(x: 752, y: 588))
    apple.curve(to: NSPoint(x: 683, y: 570), controlPoint1: NSPoint(x: 723, y: 608), controlPoint2: NSPoint(x: 687, y: 603))
    apple.curve(to: NSPoint(x: 704, y: 468), controlPoint1: NSPoint(x: 663, y: 537), controlPoint2: NSPoint(x: 672, y: 484))
    apple.curve(to: NSPoint(x: 752, y: 466), controlPoint1: NSPoint(x: 723, y: 454), controlPoint2: NSPoint(x: 733, y: 457))
    apple.curve(to: NSPoint(x: 811, y: 499), controlPoint1: NSPoint(x: 779, y: 451), controlPoint2: NSPoint(x: 799, y: 472))
    apple.curve(to: NSPoint(x: 810, y: 571), controlPoint1: NSPoint(x: 827, y: 530), controlPoint2: NSPoint(x: 825, y: 550))
    apple.curve(to: NSPoint(x: 752, y: 588), controlPoint1: NSPoint(x: 795, y: 600), controlPoint2: NSPoint(x: 770, y: 605))
    apple.close()
    NSGradient(colors: [color(0xEBA99A), color(0xD77F72)])!.draw(in: apple, angle: -30)
    stem(from: NSPoint(x: 751, y: 588), to: NSPoint(x: 748, y: 612), width: 8)
    leaf(from: NSPoint(x: 750, y: 599), to: NSPoint(x: 804, y: 628), fill: color(0x5B9E82), breadth: 18)
    oval(NSRect(x: 710, y: 535, width: 12, height: 28), colors: [color(0xF9DBCA, alpha: 0.6), color(0xF9DBCA, alpha: 0.2)])
}

func drawImage(size: Int, background: Bool) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    if background {
        let shadow = NSShadow()
        shadow.shadowColor = color(0x0B252B, alpha: 0.16)
        shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.shadowBlurRadius = 19
        shadow.set()
        let path = NSBezierPath(roundedRect: NSRect(x: 50, y: 50, width: 924, height: 924), xRadius: 203, yRadius: 203)
        color(0xF4F8F7).setFill()
        path.fill()
        NSShadow().set()
        NSGradient(colors: [color(0xF4F8F7), color(0xE7F3F0)])!.draw(in: path, angle: -90)
    } else {
        context.cgContext.translateBy(x: -135, y: -177)
        context.cgContext.scaleBy(x: 1.28, y: 1.28)
    }
    cornucopia()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

let sizes: [(String, Int)] = [("icon_16x16.png", 16), ("icon_16x16@2x.png", 32), ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64), ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256), ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512), ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)]
for (name, size) in sizes {
    try drawImage(size: size, background: true).write(to: outputDirectory.appendingPathComponent(name))
}
try drawImage(size: 256, background: false).write(to: logoURL)
print("Iconset: \(outputDirectory.path)")
print("Logo: \(logoURL.path)")
