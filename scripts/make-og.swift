import AppKit

// Draws the 1200x630 Open Graph card for mac-camera.tibeblabs.com:
// dark site-style background with amber glows, headline, and the app
// screenshot in a framed panel on the right.
// Usage: make-og <screenshot.png> <icon.png> <out.jpg>

let args = CommandLine.arguments
guard args.count == 4 else {
    FileHandle.standardError.write(Data("usage: make-og <screenshot.png> <icon.png> <out.jpg>\n".utf8))
    exit(64)
}
guard let shot = NSImage(contentsOfFile: args[1]) else { fatalError("cannot load \(args[1])") }
guard let icon = NSImage(contentsOfFile: args[2]) else { fatalError("cannot load \(args[2])") }
let out = URL(fileURLWithPath: args[3])

let W: CGFloat = 1200, H: CGFloat = 630

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let gc = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gc
let ctx = gc.cgContext

// --- background: near-black with soft amber/yellow glows ---------------------
NSColor(calibratedRed: 0.043, green: 0.043, blue: 0.059, alpha: 1).setFill()
NSBezierPath(rect: CGRect(x: 0, y: 0, width: W, height: H)).fill()

func glow(cx: CGFloat, cy: CGFloat, r: CGFloat, color: NSColor) {
    let colors = [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawRadialGradient(grad, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                           endCenter: CGPoint(x: cx, y: cy), endRadius: r, options: [])
}
glow(cx: 150, cy: H - 60, r: 500, color: NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.0, alpha: 0.12))
glow(cx: W - 220, cy: 120, r: 560, color: NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.04, alpha: 0.10))
glow(cx: W * 0.55, cy: H * 0.5, r: 700, color: NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.0, alpha: 0.05))

// faint grid, like the site's stage backdrop
NSColor(white: 1, alpha: 0.028).setStroke()
var gx: CGFloat = 0
while gx <= W {
    let p = NSBezierPath(); p.move(to: CGPoint(x: gx, y: 0)); p.line(to: CGPoint(x: gx, y: H))
    p.lineWidth = 1; p.stroke(); gx += 60
}
var gy: CGFloat = 0
while gy <= H {
    let p = NSBezierPath(); p.move(to: CGPoint(x: 0, y: gy)); p.line(to: CGPoint(x: W, y: gy))
    p.lineWidth = 1; p.stroke(); gy += 60
}

// --- right panel: the screenshot in a glass frame ----------------------------
let panelH: CGFloat = 470
let scale = panelH / shot.size.height
let panelW = shot.size.width * scale
let panelX = W - panelW - 56
let panelY = (H - panelH) / 2
let panelRect = CGRect(x: panelX, y: panelY, width: panelW, height: panelH)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 60,
              color: NSColor.black.withAlphaComponent(0.65).cgColor)
let frame = NSBezierPath(roundedRect: panelRect, xRadius: 18, yRadius: 18)
NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.09, alpha: 1).setFill()
frame.fill()
ctx.restoreGState()

NSGraphicsContext.saveGraphicsState()
NSBezierPath(roundedRect: panelRect, xRadius: 18, yRadius: 18).addClip()
shot.draw(in: panelRect, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
NSColor(white: 1, alpha: 0.14).setStroke()
let border = NSBezierPath(roundedRect: panelRect, xRadius: 18, yRadius: 18)
border.lineWidth = 1.5
border.stroke()

// --- left: brand, headline, sub ----------------------------------------------
let textX: CGFloat = 64
let yellow = NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.0, alpha: 1)
let muted = NSColor(calibratedRed: 0.60, green: 0.60, blue: 0.66, alpha: 1)

// brand row
icon.draw(in: CGRect(x: textX, y: H - 118, width: 54, height: 54),
          from: .zero, operation: .sourceOver, fraction: 1)
("Camera" as NSString).draw(
    at: CGPoint(x: textX + 66, y: H - 108),
    withAttributes: [.font: NSFont.systemFont(ofSize: 30, weight: .bold),
                     .foregroundColor: NSColor.white])

// headline
let headline1 = "The camera app"
let headline2 = "macOS never"
let headline3 = "shipped."
let hFont = NSFont.systemFont(ofSize: 58, weight: .heavy)
(headline1 as NSString).draw(at: CGPoint(x: textX, y: 358),
    withAttributes: [.font: hFont, .foregroundColor: NSColor.white])
(headline2 as NSString).draw(at: CGPoint(x: textX, y: 292),
    withAttributes: [.font: hFont, .foregroundColor: yellow])
(headline3 as NSString).draw(at: CGPoint(x: textX, y: 226),
    withAttributes: [.font: hFont, .foregroundColor: yellow])

// sub lines
let sFont = NSFont.systemFont(ofSize: 21, weight: .medium)
("Free & open source · MIT" as NSString).draw(at: CGPoint(x: textX, y: 168),
    withAttributes: [.font: sFont, .foregroundColor: muted])
("Signed & notarized · macOS 14+" as NSString).draw(at: CGPoint(x: textX, y: 136),
    withAttributes: [.font: sFont, .foregroundColor: muted])

// url pill
let pillText = "mac-camera.tibeblabs.com" as NSString
let pFont = NSFont.systemFont(ofSize: 19, weight: .semibold)
let pSize = pillText.size(withAttributes: [.font: pFont])
let pillRect = CGRect(x: textX, y: 72, width: pSize.width + 40, height: 40)
NSColor(white: 1, alpha: 0.06).setFill()
NSBezierPath(roundedRect: pillRect, xRadius: 20, yRadius: 20).fill()
NSColor(white: 1, alpha: 0.14).setStroke()
let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 20, yRadius: 20)
pillPath.lineWidth = 1
pillPath.stroke()
pillText.draw(at: CGPoint(x: pillRect.minX + 20, y: pillRect.minY + 9),
    withAttributes: [.font: pFont, .foregroundColor: yellow])

NSGraphicsContext.restoreGraphicsState()
let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])!
try! jpg.write(to: out)
