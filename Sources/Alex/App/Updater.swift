import AppKit
import Combine
import Security
import Sparkle

/// Alex updates itself through Sparkle (revision 68): once a day, and from
/// "Check for updates…" under About and in Settings, it reads the appcast
/// that `release.yml` publishes with each release here, and offers a
/// newer build in Sparkle's own window. Sparkle accepts an update only if
/// its EdDSA signature matches `SUPublicEDKey` and its code signature
/// matches this copy's. A build made here is not Developer ID signed, so
/// its updater never starts and never swaps a release over a dev build.
@MainActor
final class Updater: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = Updater()

    /// Liam's team, from the Developer ID certificate's OU.
    static let team = "3Y4L9KSVBD"
    static let downloadsPage = URL(string: "https://liamle.me/alex")!

    @Published private(set) var canCheck = false
    @Published var automatic = false {
        didSet {
            if controller.updater.automaticallyChecksForUpdates != automatic {
                controller.updater.automaticallyChecksForUpdates = automatic
            }
        }
    }

    /// Whether this copy is a Developer ID release: only those update.
    let isRelease: Bool
    private var controller: SPUStandardUpdaterController!
    private var watching: AnyCancellable?

    private override init() {
        isRelease = Self.selfIsDeveloperID()
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self,
                                                  userDriverDelegate: nil)
    }

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
    var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// At launch. `--update-check now` starts the updater on any build and
    /// checks at once, with `--update-feed <url>` for another appcast, so
    /// the flow can be tried on a build made here. `--update-check install`
    /// with `-SUAutomaticallyUpdate YES` downloads in the background and
    /// installs and relaunches as soon as the update is ready, no clicks.
    func start() {
        let flag = Launch.value(after: "--update-check")
        if flag == "install" {
            controller.startUpdater()
            controller.updater.checkForUpdatesInBackground()
            return
        }
        let forced = flag == "now"
        guard isRelease || forced else { return }
        controller.startUpdater()
        automatic = controller.updater.automaticallyChecksForUpdates
        watching = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheck = $0 }
        if forced { controller.updater.checkForUpdates() }
    }

    func check() {
        guard isRelease || canCheck else {
            let alert = NSAlert()
            alert.messageText = "This copy of Alex doesn't update itself"
            alert.informativeText = "Only a signed release does. This one was built on this Mac."
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Open downloads")
            if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(Self.downloadsPage) }
            return
        }
        controller.checkForUpdates(nil)
    }

    // MARK: SPUUpdaterDelegate

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        Launch.value(after: "--update-feed")
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                             immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        guard Launch.value(after: "--update-check") == "install" else { return false }
        immediateInstallHandler()
        return true
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        FileHandle.standardError.write(Data("update: \(error.localizedDescription)\n".utf8))
    }

    // MARK: Signatures

    /// A Developer ID application of this team: Apple's root, the Developer
    /// ID intermediate and leaf markers, the team. Apple Development and
    /// ad-hoc signatures do not meet it.
    private static func selfIsDeveloperID() -> Bool {
        let text = "anchor apple generic"
            + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
            + " and certificate leaf[subject.OU] = \"\(team)\""
        var me: SecCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        return SecCodeCheckValidity(me, [], requirement) == errSecSuccess
    }
}
