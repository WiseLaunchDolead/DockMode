import AppKit
import DockModeCore
import OSLog

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let showManager: (Bool) -> Void
    private let checkForUpdates: () -> Void
    private let canCheckForUpdates: () -> Bool
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let logger = Logger(subsystem: "fr.wiselaunch.DockMode", category: "StatusBar")

    init(
        model: AppModel,
        showManager: @escaping (Bool) -> Void,
        checkForUpdates: @escaping () -> Void,
        canCheckForUpdates: @escaping () -> Bool
    ) {
        self.model = model
        self.showManager = showManager
        self.checkForUpdates = checkForUpdates
        self.canCheckForUpdates = canCheckForUpdates
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.autosaveName = "fr.wiselaunch.DockMode.StatusItem"
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.image = StatusBarIconRenderer.image()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.imageScaling = .scaleNone
        statusItem.isVisible = true
        rebuildMenu()

        logger.notice("Status item installed; visible: \(self.statusItem.isVisible, privacy: .public)")
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        updateAccessibilityLabel()

        let header = NSMenuItem(title: localized("Docks"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for profile in model.profiles {
            let item = NSMenuItem(
                title: profile.name,
                action: #selector(selectProfile(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = profile.id.uuidString
            item.state = profile.id == model.document.activeProfileID ? .on : .off
            item.image = ProfileMenuIconRenderer.image(for: profile.color)
            item.isEnabled = !model.isSwitching
            menu.addItem(item)
        }

        if model.profiles.isEmpty {
            menu.addItem(commandItem(
                title: localized("Finish DockMode Setup…"),
                symbolName: "wand.and.stars",
                action: #selector(finishSetup)
            ))
        }

        if !model.missingApplications.isEmpty {
            menu.addItem(.separator())
            let warning = NSMenuItem(
                title: localized("Some profile applications are unavailable"),
                action: nil,
                keyEquivalent: ""
            )
            warning.image = symbol(named: "exclamationmark.triangle")
            warning.isEnabled = false
            menu.addItem(warning)
        }

        menu.addItem(.separator())
        let newProfile = commandItem(
            title: localized("New Profile…"),
            symbolName: "plus.circle",
            action: #selector(createProfile)
        )
        newProfile.isEnabled = !model.profiles.isEmpty
        menu.addItem(newProfile)
        menu.addItem(commandItem(
            title: localized("Manage Profiles…"),
            symbolName: "slider.horizontal.3",
            action: #selector(manageProfiles)
        ))

        menu.addItem(.separator())
        let updates = commandItem(
            title: localized("Check for Updates…"),
            symbolName: "arrow.triangle.2.circlepath",
            action: #selector(checkForUpdatesAction)
        )
        updates.isEnabled = canCheckForUpdates()
        menu.addItem(updates)

        if model.launchAtLoginState == .requiresApproval {
            let warning = NSMenuItem(
                title: localized("Launch at login requires approval in System Settings"),
                action: nil,
                keyEquivalent: ""
            )
            warning.image = symbol(named: "exclamationmark.triangle")
            warning.isEnabled = false
            menu.addItem(warning)
        }

        menu.addItem(.separator())
        let quit = commandItem(
            title: localized("Quit DockMode"),
            symbolName: "power",
            action: #selector(quitDockMode),
            keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = .command
        menu.addItem(quit)
    }

    private func commandItem(
        title: String,
        symbolName: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.image = symbol(named: symbolName)
        item.isEnabled = true
        return item
    }

    private func symbol(named name: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }

    private func updateAccessibilityLabel() {
        let label: String
        if let profileName = model.activeProfile?.name {
            label = String(
                format: localized("DockMode, active profile: %@"),
                profileName
            )
        } else {
            label = localized("DockMode")
        }
        statusItem.button?.setAccessibilityLabel(label)
        statusItem.button?.toolTip = label
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let profileID = UUID(uuidString: value),
              profileID != model.document.activeProfileID else { return }

        do {
            try model.switchProfile(to: profileID)
        } catch {
            model.presentError(error)
        }
    }

    @objc private func finishSetup() {
        showManager(false)
    }

    @objc private func createProfile() {
        showManager(true)
    }

    @objc private func manageProfiles() {
        showManager(false)
    }

    @objc private func checkForUpdatesAction() {
        checkForUpdates()
    }

    @objc private func quitDockMode() {
        NSApplication.shared.terminate(nil)
    }
}
