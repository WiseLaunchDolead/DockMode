import AppKit
import SwiftUI

@main
struct DockModeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
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
                contentRect: NSRect(x: 0, y: 0, width: 1_050, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "DockMode"
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
