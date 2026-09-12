import Foundation
import CoreServices

/// FSEvents over the vault root: absolute paths of what changed, debounced by
/// the system to `latency`, delivered on a private queue. The `Vault` hops
/// them to the main actor and drops the echo of its own writes.
final class VaultWatcher {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.liamlee.alex.fsevents")
    private let onChange: @Sendable ([String]) -> Void

    init(root: URL, latency: TimeInterval = 0.3,
         onChange: @escaping @Sendable ([String]) -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<VaultWatcher>.fromOpaque(info).takeUnretainedValue()
            let array = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as NSArray
            let paths = (array as? [String] ?? []).prefix(count)
            watcher.onChange(Array(paths))
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagUseCFTypes
            | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [root.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else {
            return
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    deinit { stop() }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
