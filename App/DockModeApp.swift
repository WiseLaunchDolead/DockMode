import AppKit
import DockModeCore
import SwiftUI

@main
@MainActor
enum DockModeApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let updater = UpdaterController()
    private var managerWindowController: NSWindowController?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        model.start()
        statusBarController = StatusBarController(
            model: model,
            showManager: { [weak self] createNewProfile in
                self?.showManager(createNewProfile: createNewProfile)
            },
            checkForUpdates: { [weak self] in
                self?.updater.checkForUpdates()
            },
            canCheckForUpdates: { [weak self] in
                self?.updater.canCheckForUpdates ?? false
            }
        )
        if model.needsOnboarding {
            showManager(createNewProfile: false)
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            showManager(createNewProfile: false)
        }
        return true
    }

    func showManager(createNewProfile: Bool) {
        if managerWindowController == nil {
            let rootView = ProfileManagementView(model: model)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 420),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "DockMode"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unifiedCompact
            window.isOpaque = false
            window.backgroundColor = .clear
            DockEditorWindowInteraction.configure(window)
            window.minSize = NSSize(width: 720, height: 360)
            window.center()
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: rootView)
            managerWindowController = NSWindowController(window: window)
        }

        managerWindowController?.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if createNewProfile {
            model.isPresentingNewProfile = true
        }
    }
}
