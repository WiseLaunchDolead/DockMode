import AppKit
import Foundation

public enum ApplicationCatalog {
    public static func discover(
        roots: [URL] = defaultRoots,
        fileManager: FileManager = .default
    ) -> [ApplicationReference] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentTypeKey]
        var applicationsByKey: [String: ApplicationReference] = [:]

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()

                let bundle = Bundle(url: url)
                let displayName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let reference = ApplicationReference(
                    bundleIdentifier: bundle?.bundleIdentifier,
                    displayName: displayName,
                    lastKnownPath: url.standardizedFileURL.path
                )
                applicationsByKey[reference.stableKey] = reference
            }
        }

        return applicationsByKey.values.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    public static var defaultRoots: [URL] {
        var roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true)
        ]
        roots.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"))
        return roots
    }
}

public protocol ApplicationResolving: AnyObject {
    func resolve(_ reference: ApplicationReference) -> URL?
}

public final class WorkspaceApplicationResolver: ApplicationResolving {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func resolve(_ reference: ApplicationReference) -> URL? {
        let knownURL = URL(fileURLWithPath: reference.lastKnownPath).standardizedFileURL
        if fileManager.fileExists(atPath: knownURL.path),
           reference.bundleIdentifier == nil || Bundle(url: knownURL)?.bundleIdentifier == reference.bundleIdentifier {
            return knownURL
        }

        if let bundleIdentifier = reference.bundleIdentifier,
           let workspaceURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return workspaceURL.standardizedFileURL
        }

        return nil
    }
}
