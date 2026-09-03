import Foundation

#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
final class UpdaterController {
#if canImport(Sparkle)
    private let controller: SPUStandardUpdaterController?

    init() {
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        guard let publicKey, !publicKey.isEmpty, !publicKey.hasPrefix("$(") else {
            controller = nil
            return
        }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
#else
    init() {}
    var canCheckForUpdates: Bool { false }
    func checkForUpdates() {}
#endif
}
