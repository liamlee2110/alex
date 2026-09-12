// Draws the step response of a first-order plant under a P controller and
// writes it as PNG: the kind of artifact the coach makes in a session.
// usage: swift tools/step-response.swift out.png [Kp]
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "step.png"
let kp = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2]) ?? 2.0 : 2.0
let width = 960.0, height = 600.0
let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
ctx.setFillColor(NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1).cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

let left = 90.0, right = width - 40, bottom = 80.0, top = height - 60
ctx.setStrokeColor(NSColor(white: 0.85, alpha: 1).cgColor)
ctx.setLineWidth(1)
for i in 0...5 {
    let y = bottom + (top - bottom) * Double(i) / 5
    ctx.move(to: CGPoint(x: left, y: y)); ctx.addLine(to: CGPoint(x: right, y: y))
}
ctx.strokePath()

// Plant: tau·dy/dt + y = u, u = Kp·(r − y), r = 1. Euler at dt.
let tau = 1.0, dt = 0.01, seconds = 6.0
var y = 0.0
var points: [CGPoint] = []
var t = 0.0
while t <= seconds {
    let u = kp * (1 - y)
    y += dt * (u - y) / tau
    let px = left + (right - left) * t / seconds
    let py = bottom + (top - bottom) * (y / 1.2)
    points.append(CGPoint(x: px, y: py))
    t += dt
}
ctx.setStrokeColor(NSColor(srgbRed: 0.06, green: 0.42, blue: 0.74, alpha: 1).cgColor)
ctx.setLineWidth(3)
ctx.addLines(between: points)
ctx.strokePath()
// The setpoint.
ctx.setStrokeColor(NSColor(srgbRed: 0.8, green: 0.3, blue: 0.2, alpha: 1).cgColor)
ctx.setLineWidth(1.5)
ctx.setLineDash(phase: 0, lengths: [8, 6])
let setY = bottom + (top - bottom) * (1 / 1.2)
ctx.move(to: CGPoint(x: left, y: setY)); ctx.addLine(to: CGPoint(x: right, y: setY))
ctx.strokePath()

let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.black]
NSAttributedString(string: "Step response, P control, Kp = \(kp), tau = \(tau) s", attributes: attrs)
    .draw(at: CGPoint(x: left, y: height - 40))
let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.darkGray]
NSAttributedString(string: "steady-state error \(String(format: "%.2f", 1 - y)) — a P controller alone never reaches the setpoint", attributes: small)
    .draw(at: CGPoint(x: left, y: 30))
for i in 0...6 {
    NSAttributedString(string: "\(i) s", attributes: small)
        .draw(at: CGPoint(x: left + (right - left) * Double(i) / 6 - 8, y: bottom - 24))
}
image.unlockFocus()
let tiff = image.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
