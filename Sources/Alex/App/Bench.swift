import AppKit
import QuartzCore

/// `--bench pan|zoom|both` (and `--bench-delay <seconds>`, 2.5 by
/// default, before it starts): moves the desk's camera once per display frame
/// for a few seconds, the way a trackpad does, and prints how long each frame
/// took, then quits. A frame that takes longer than the display's refresh is
/// a frame the pointer saw stutter. Run it in the foreground, like a
/// snapshot: a backgrounded process never gets a window.
@MainActor
final class Bench: NSObject {
    static let mode = Launch.value(after: "--bench")
    private static var running: Bench?

    private let store: CanvasStore
    private let mode: String
    private var link: CADisplayLink?
    private var stamps: [CFTimeInterval] = []
    private var step = 0
    private let steps = 360

    private init(store: CanvasStore, mode: String) {
        self.store = store
        self.mode = mode
    }

    static func start(store: CanvasStore) {
        guard let mode, running == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + (Launch.value(after: "--bench-delay").flatMap(Double.init) ?? 2.5)) {
            let bench = Bench(store: store, mode: mode)
            running = bench
            bench.begin()
        }
    }

    private func begin() {
        guard let screen = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) })?.screen ?? NSScreen.main else { return }
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        stamps.append(CACurrentMediaTime())
        let size = store.viewSize
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let phase = Double(step) / Double(steps) * 2 * .pi
        let zooming = mode == "zoom" || (mode == "both" && step % 2 == 1)
        if zooming {
            store.viewport.zoom(by: 1 + 0.012 * cos(phase * 2), around: centre)
        } else {
            store.viewport.pan(by: CGPoint(x: 9 * cos(phase), y: 6 * sin(phase)))
        }
        step += 1
        if step > steps { finish(refresh: link.duration) }
    }

    private func finish(refresh: CFTimeInterval) {
        link?.invalidate()
        let frames = zip(stamps.dropFirst(), stamps).map { ($0 - $1) * 1000 }.sorted()
        func at(_ q: Double) -> Double { frames[min(frames.count - 1, Int(Double(frames.count) * q))] }
        let budget = refresh * 1000
        let dropped = frames.filter { $0 > budget * 1.5 }.count
        let total = (stamps.last! - stamps.first!)
        let line = String(format: "bench %@: %d frames in %.2fs, %.0f fps; frame ms median %.1f p90 %.1f p99 %.1f max %.1f; %d over %.1fms\n",
                          mode, frames.count, total, Double(frames.count) / total,
                          at(0.5), at(0.9), at(0.99), frames.last ?? 0, dropped, budget * 1.5)
        FileHandle.standardError.write(Data(line.utf8))
        NSApp.terminate(nil)
    }
}
