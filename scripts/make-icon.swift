import AppKit

// Draws the Camera app icon at the given canvas size and writes a PNG.
// Usage: make-icon <size> <output.png>

let args = CommandLine.arguments
guard args.count == 3, let size = Int(args[1]) else {
    FileHandle.standardError.write(Data("usage: make-icon <size> <out.png>\n".utf8))
    exit(64)
}
let out = URL(fileURLWithPath: args[2])
let S = CGFloat(size)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let gc = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gc
let ctx = gc.cgContext

// Squircle plate: macOS icon grid keeps ~10% transparent margin.
let margin = S * 0.10
let plate = CGRect(x: margin, y: margin, width: S - 2 * margin, height: S - 2 * margin)
let corner = plate.width * 0.2237
let platePath = NSBezierPath(roundedRect: plate, xRadius: corner, yRadius: corner)

// Dark glass background gradient.
platePath.addClip()
let bg = NSGradient(colors: [NSColor(calibratedRed: 0.17, green: 0.17, blue: 0.19, alpha: 1),
                             NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.10, alpha: 1)])!
bg.draw(in: plate, angle: -90)

// Lens: concentric rings centered on the plate.
let c = CGPoint(x: plate.midX, y: plate.midY)
func circle(_ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: CGRect(x: c.x - radius, y: c.y - radius, width: 2 * radius, height: 2 * radius))
}
let rOuter = plate.width * 0.34

// Outer barrel ring.
NSColor(white: 0.30, alpha: 1).setStroke()
let barrel = circle(rOuter); barrel.lineWidth = S * 0.015; barrel.stroke()

// Glass body.
let body = circle(rOuter * 0.92)
let bodyGrad = NSGradient(colors: [NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.20, alpha: 1),
                                   NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.08, alpha: 1)])!
bodyGrad.draw(in: body, angle: -70)

// Accent ring (Theme.accent yellow).
NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.04, alpha: 0.95).setStroke()
let accent = circle(rOuter * 0.72); accent.lineWidth = S * 0.022; accent.stroke()

// Inner pupil.
let pupil = circle(rOuter * 0.45)
NSGradient(colors: [NSColor(calibratedRed: 0.22, green: 0.30, blue: 0.45, alpha: 1),
                    NSColor.black])!.draw(in: pupil, angle: -60)

// Specular highlight, upper-left.
let hl = NSBezierPath(ovalIn: CGRect(x: c.x - rOuter * 0.52, y: c.y + rOuter * 0.10,
                                     width: rOuter * 0.52, height: rOuter * 0.40))
NSColor(white: 1, alpha: 0.28).setFill(); hl.fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
