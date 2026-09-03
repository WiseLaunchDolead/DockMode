import Foundation

public enum DockModeConstants {
    public static let appGroupIdentifier = "group.fr.wiselaunch.DockMode"
    public static let dockDomain = "com.apple.dock"
    public static let dockAppsKey = "persistent-apps"
    public static let profileDocumentName = "profiles.json"
    public static let focusRequestName = "focus-request.json"
    public static let focusNotificationName = "fr.wiselaunch.DockMode.focus-requested"
    public static let schemaVersion = 1
}

public enum DockModeStorage {
    public static func sharedContainerURL(fileManager: FileManager = .default) -> URL {
        if let groupURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: DockModeConstants.appGroupIdentifier
        ) {
            return groupURL
        }

        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL.appendingPathComponent("DockMode", isDirectory: true)
    }
}
