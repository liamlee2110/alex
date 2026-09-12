// Crops the window chrome off a snapshot: usage swift tools/crop-top.swift in.png out.png [pixels]
import AppKit
let args = CommandLine.arguments
let source = URL(fileURLWithPath: args[1]), dest = URL(fileURLWithPath: args[2])
let top = args.count > 3 ? Int(args[3]) ?? 104 : 104
guard let image = NSImage(contentsOf: source), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { exit(1) }
let rect = CGRect(x: 0, y: top, width: cg.width, height: cg.height - top)
guard let cropped = cg.cropping(to: rect) else { exit(1) }
let rep = NSBitmapImageRep(cgImage: cropped)
try! rep.representation(using: .png, properties: [:])!.write(to: dest)
print("cropped \(dest.lastPathComponent) to \(cropped.width)x\(cropped.height)")
