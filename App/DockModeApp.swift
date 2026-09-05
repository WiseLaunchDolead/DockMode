import AppKit
import DockModeCore
import SwiftUI

@main
struct DockModeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra(isInserted: .constant(true)) {
            MenuBarContentView(
                model: appDelegate.model,
                showManager: { newProfile in
                    appDelegate.showManager(createNewProfile: newProfile)
                },
                checkForUpdates: { appDelegate.updater.checkForUpdates() },
                canCheckForUpdates: appDelegate.updater.canCheckForUpdates
            )
        } label: {
            Image(systemName: "rectangle.3.group")
                .accessibilityLabel(accessibilityLabel)
        }
        .menuBarExtraStyle(.menu)
    }

    private var accessibilityLabel: Text {
        if let profileName = appDelegate.model.activeProfile?.name {
            Text("DockMode, active profile: \(profileName)")
        } else {
            Text("DockMode")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let updater = UpdaterController()
    private var managerWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        model.start()
        if model.needsOnboarding {
            showManager(createNewProfile: false)
        }
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
