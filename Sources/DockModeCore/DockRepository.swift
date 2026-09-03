import AppKit
import CoreFoundation
import Foundation

public enum DockRepositoryError: Error, LocalizedError {
    case unreadablePreferences
    case synchronizationFailed
    case verificationFailed

    public var errorDescription: String? {
        switch self {
        case .unreadablePreferences:
            NSLocalizedString(
                "DockMode could not read the pinned Dock applications.",
                bundle: .main,
                comment: "Dock read error"
            )
        case .synchronizationFailed:
            NSLocalizedString(
                "macOS refused to save the Dock configuration.",
                bundle: .main,
                comment: "Dock write error"
            )
        case .verificationFailed:
            NSLocalizedString(
                "The Dock did not accept the requested profile. The previous Dock was restored.",
                bundle: .main,
                comment: "Dock rollback error"
            )
        }
    }
}

public struct DockApplyResult {
    public var appliedItems: [DockItem]
    public var missingApplications: [ApplicationReference]

    public init(appliedItems: [DockItem], missingApplications: [ApplicationReference]) {
        self.appliedItems = appliedItems
        self.missingApplications = missingApplications
    }
}

public final class DockCodec {
    public init() {}

    public func decode(_ rawItems: [[String: Any]]) -> [DockItem] {
        rawItems.compactMap { rawItem in
            guard let tileType = rawItem["tile-type"] as? String else { return nil }
            if let spacerKind = SpacerKind(dockTileType: tileType) {
                return .spacer(spacerKind)
            }

            guard tileType == "file-tile",
                  let tileData = rawItem["tile-data"] as? [String: Any],
                  let fileData = tileData["file-data"] as? [String: Any],
                  let rawPath = fileData["_CFURLString"] as? String,
                  let path = normalizedPath(rawPath) else {
                return nil
            }

            let bundleIdentifier = tileData["bundle-identifier"] as? String
                ?? Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
            guard bundleIdentifier != nil || path.lowercased().contains(".app") else { return nil }

            let label = tileData["file-label"] as? String
                ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            return .application(ApplicationReference(
                bundleIdentifier: bundleIdentifier,
                displayName: label,
                lastKnownPath: path
            ))
        }
    }

    public func encode(
        _ items: [DockItem],
        resolvingWith resolver: ApplicationResolving
    ) -> (rawItems: [[String: Any]], appliedItems: [DockItem], missing: [ApplicationReference]) {
        var rawItems: [[String: Any]] = []
        var appliedItems: [DockItem] = []
        var missing: [ApplicationReference] = []

        for item in items {
            switch item.content {
            case let .spacer(kind):
                rawItems.append([
                    "GUID": randomGUID(),
                    "tile-data": [String: Any](),
                    "tile-type": kind.dockTileType
                ])
                appliedItems.append(item)

            case let .application(reference):
                guard let applicationURL = resolver.resolve(reference) else {
                    missing.append(reference)
                    continue
                }
                let bundle = Bundle(url: applicationURL)
                let bundleIdentifier = bundle?.bundleIdentifier ?? reference.bundleIdentifier
                let displayName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? reference.displayName

                var tileData: [String: Any] = [
                    "file-data": [
                        "_CFURLString": applicationURL.standardizedFileURL.path,
                        "_CFURLStringType": 0
                    ],
                    "file-label": displayName,
                    "file-type": 41
                ]
                if let bundleIdentifier {
                    tileData["bundle-identifier"] = bundleIdentifier
                }
                rawItems.append([
                    "GUID": randomGUID(),
                    "tile-data": tileData,
                    "tile-type": "file-tile"
                ])

                var updatedItem = item
                updatedItem.content = .application(ApplicationReference(
                    bundleIdentifier: bundleIdentifier,
                    displayName: displayName,
                    lastKnownPath: applicationURL.standardizedFileURL.path
                ))
                appliedItems.append(updatedItem)
            }
        }

        return (rawItems, appliedItems, missing)
    }

    public func fingerprint(_ items: [DockItem]) -> String {
        items.map(\.matchingKey).joined(separator: "\u{1F}")
    }

    private func normalizedPath(_ value: String) -> String? {
        if let url = URL(string: value), url.isFileURL {
            return url.standardizedFileURL.path
        }
        guard !value.isEmpty else { return nil }
        return URL(fileURLWithPath: value).standardizedFileURL.path
    }

    private func randomGUID() -> Int {
        Int.random(in: 1_000_000_000...Int(Int32.max))
    }
}

public protocol DockPreferencesAccess: AnyObject {
    func readPinnedItems() throws -> [[String: Any]]
    func writePinnedItems(_ items: [[String: Any]]) throws
    func restartDock()
}

public final class SystemDockPreferencesAccess: DockPreferencesAccess {
    private let domain: String
    private let key: String

    public init(
        domain: String = DockModeConstants.dockDomain,
        key: String = DockModeConstants.dockAppsKey
    ) {
        self.domain = domain
        self.key = key
    }

    public func readPinnedItems() throws -> [[String: Any]] {
        guard let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString)
            as? [[String: Any]] else {
            throw DockRepositoryError.unreadablePreferences
        }
        return value
    }

    public func writePinnedItems(_ items: [[String: Any]]) throws {
        CFPreferencesSetAppValue(key as CFString, items as CFPropertyList, domain as CFString)
        let didSynchronize = CFPreferencesSynchronize(
            domain as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        guard didSynchronize else { throw DockRepositoryError.synchronizationFailed }
    }

    public func restartDock() {
        if let dock = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.dock"
        }), dock.terminate() {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        try? process.run()
    }
}

public final class DockRepository {
    private let preferences: DockPreferencesAccess
    private let resolver: ApplicationResolving
    public let codec: DockCodec

    public init(
        preferences: DockPreferencesAccess = SystemDockPreferencesAccess(),
        resolver: ApplicationResolving = WorkspaceApplicationResolver(),
        codec: DockCodec = DockCodec()
    ) {
        self.preferences = preferences
        self.resolver = resolver
        self.codec = codec
    }

    public func currentItems() throws -> [DockItem] {
        codec.decode(try preferences.readPinnedItems())
    }

    public func missingApplications(in items: [DockItem]) -> [ApplicationReference] {
        codec.encode(items, resolvingWith: resolver).missing
    }

    public func apply(_ requestedItems: [DockItem]) throws -> DockApplyResult {
        let backup = try preferences.readPinnedItems()
        let encoded = codec.encode(requestedItems, resolvingWith: resolver)

        do {
            try preferences.writePinnedItems(encoded.rawItems)
            preferences.restartDock()
            let verified = codec.decode(try preferences.readPinnedItems())
            guard codec.fingerprint(verified) == codec.fingerprint(encoded.appliedItems) else {
                throw DockRepositoryError.verificationFailed
            }
            return DockApplyResult(
                appliedItems: encoded.appliedItems,
                missingApplications: encoded.missing
            )
        } catch {
            try? preferences.writePinnedItems(backup)
            preferences.restartDock()
            throw error
        }
    }
}
