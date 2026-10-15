// Builds AppIcon.icns from square art on Apple's macOS icon grid: the art
// is cut to a continuous-corner square of 824 on a 1024 canvas, with the
// system's drop shadow, so it sits in the Dock at the size and roundness
// of its neighbours instead of filling the whole tile.
//
//   swift tools/make-icon.swift docs/logo/alex-app-icon-tile.png AppIcon
//
// writes AppIcon.png (the 1024 master) and AppIcon.icns.
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let art = NSImage(contentsOfFile: args[1]),
      let artCG = art.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("usage: make-icon.swift <art.png> <out-basename>\n".data(using: .utf8)!)
    exit(1)
}
let out = args[2]

// The squircle: a superellipse with exponent 5 matches the system shape
// closely at every size the Dock draws.
func squircle(_ r: CGRect) -> CGPath {
    let p = CGMutablePath(), n = 5.0, steps = 720
    for i in 0..<steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = pow(abs(c), 2 / n) * (c < 0 ? -1 : 1)
        let y = pow(abs(s), 2 / n) * (s < 0 ? -1 : 1)
        let pt = CGPoint(x: r.midX + x * r.width / 2, y: r.midY + y * r.height / 2)
        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath()
    return p
}

func render(_ size: Int) -> CGImage {
    let s = CGFloat(size) / 1024
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let body = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = squircle(body)
    // Apple's template shadow: black at 30%, 10 down, 10 blur.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 10 * s,
                  color: CGColor(gray: 0, alpha: 0.3))
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.draw(artCG, in: body)
    return ctx.makeImage()!
}

func write(_ img: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let fm = FileManager.default
let set = NSTemporaryDirectory() + "AppIcon-\(getpid()).iconset"
try? fm.removeItem(atPath: set)
try! fm.createDirectory(atPath: set, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    write(render(pt), "\(set)/icon_\(pt)x\(pt).png")
    write(render(pt * 2), "\(set)/icon_\(pt)x\(pt)@2x.png")
}
write(render(1024), "\(out).png")

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", set, "-o", "\(out).icns"]
try! iconutil.run()
iconutil.waitUntilExit()
try? fm.removeItem(atPath: set)
exit(iconutil.terminationStatus)
