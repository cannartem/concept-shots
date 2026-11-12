import Cocoa
// Draws the 1024x1024 app icon: dark rounded square, a desktop screen and a phone in front of it with an orange screen.
let S = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let bg = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
let orange = NSColor(srgbRed: 1.0, green: 0.416, blue: 0.0, alpha: 1)
bg.setFill()
NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185).fill()

// coordinates are given from the top edge, like on a web page
func R(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x, y: CGFloat(S) - top - h, width: w, height: h)
}
func rounded(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius) }
let line: CGFloat = 32
let dx: CGFloat = 25   // centers the whole picture

NSColor.white.setStroke()
// screen
let screen = rounded(R(215 + dx, 300, 520, 340), 40)
screen.lineWidth = line; screen.stroke()
// stand
let neck = NSBezierPath()
neck.move(to: NSPoint(x: 475 + dx, y: CGFloat(S) - 646)); neck.line(to: NSPoint(x: 475 + dx, y: CGFloat(S) - 712))
neck.lineWidth = line; neck.stroke()
let base = NSBezierPath()
base.move(to: NSPoint(x: 395 + dx, y: CGFloat(S) - 712)); base.line(to: NSPoint(x: 555 + dx, y: CGFloat(S) - 712))
base.lineWidth = line; base.lineCapStyle = .round; base.stroke()

// phone: a gap in the dark colour around it, orange screen, white outline
let phone = R(575 + dx, 430, 190, 350)
bg.setFill()
rounded(phone.insetBy(dx: -34, dy: -34), 80).fill()
orange.setFill()
rounded(phone, 46).fill()
let outline = rounded(phone, 46)
outline.lineWidth = line; outline.stroke()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
