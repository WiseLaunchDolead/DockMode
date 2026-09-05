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
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    let updater = UpdaterController()
    private var managerWindowController: NSWindowController?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        installMainMenu()
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
        NSApplication.shared.setActivationPolicy(.regular)

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
            window.delegate = self
            window.contentViewController = NSHostingController(rootView: rootView)
            managerWindowController = NSWindowController(window: window)
        }

        managerWindowController?.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if createNewProfile {
            model.isPresentingNewProfile = true
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === managerWindowController?.window else { return }

        // Wait until AppKit has completed the close cycle before removing the Dock
        // presence and application menus. The menu-bar status item remains active.
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.managerWindowController?.window?.isVisible == false else { return }
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }

    private func installMainMenu() {
        let mainMenu = NSMenu(title: "Main Menu")

        let applicationMenuItem = NSMenuItem(title: "DockMode", action: nil, keyEquivalent: "")
        let applicationMenu = NSMenu(title: "DockMode")
        applicationMenu.addItem(menuItem(
            title: localized("About DockMode"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            target: NSApplication.shared
        ))
        applicationMenu.addItem(.separator())

        let servicesItem = NSMenuItem(title: localized("Services"), action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: localized("Services"))
        servicesItem.submenu = servicesMenu
        applicationMenu.addItem(servicesItem)
        NSApplication.shared.servicesMenu = servicesMenu

        applicationMenu.addItem(.separator())
        applicationMenu.addItem(menuItem(
            title: localized("Hide DockMode"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h",
            target: NSApplication.shared
        ))
        let hideOthers = menuItem(
            title: localized("Hide Others"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h",
            target: NSApplication.shared
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        applicationMenu.addItem(hideOthers)
        applicationMenu.addItem(menuItem(
            title: localized("Show All"),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            target: NSApplication.shared
        ))
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(menuItem(
            title: localized("Quit DockMode"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q",
            target: NSApplication.shared
        ))
        applicationMenuItem.submenu = applicationMenu
        mainMenu.addItem(applicationMenuItem)

        let fileMenuItem = NSMenuItem(title: localized("File"), action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: localized("File"))
        fileMenu.addItem(menuItem(
            title: localized("Close Window"),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        ))
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenuItem = NSMenuItem(title: localized("Edit"), action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: localized("Edit"))
        editMenu.addItem(menuItem(title: localized("Undo"), action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = menuItem(title: localized("Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(menuItem(title: localized("Cut"), action: Selector(("cut:")), keyEquivalent: "x"))
        editMenu.addItem(menuItem(title: localized("Copy"), action: Selector(("copy:")), keyEquivalent: "c"))
        editMenu.addItem(menuItem(title: localized("Paste"), action: Selector(("paste:")), keyEquivalent: "v"))
        editMenu.addItem(menuItem(title: localized("Select All"), action: Selector(("selectAll:")), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem(title: localized("Window"), action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: localized("Window"))
        windowMenu.addItem(menuItem(
            title: localized("Minimize"),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        ))
        windowMenu.addItem(menuItem(title: localized("Zoom"), action: #selector(NSWindow.performZoom(_:))))
        windowMenu.addItem(.separator())
        windowMenu.addItem(menuItem(
            title: localized("Bring All to Front"),
            action: #selector(NSApplication.arrangeInFront(_:)),
            target: NSApplication.shared
        ))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApplication.shared.windowsMenu = windowMenu

        let helpMenuItem = NSMenuItem(title: localized("Help"), action: nil, keyEquivalent: "")
        let helpMenu = NSMenu(title: localized("Help"))
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        NSApplication.shared.helpMenu = helpMenu

        NSApplication.shared.mainMenu = mainMenu
    }

    private func menuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        if !keyEquivalent.isEmpty {
            item.keyEquivalentModifierMask = .command
        }
        return item
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}
