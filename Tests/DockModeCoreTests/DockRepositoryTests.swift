import DockModeCore
import CoreFoundation
import Foundation
import XCTest

final class DockRepositoryTests: XCTestCase {
    func testCodecReadsOnlyApplicationsAndNativeSpacers() {
        let codec = DockCodec()
        let raw: [[String: Any]] = [
            applicationTile(path: "/Applications/Claude.app", bundleIdentifier: "com.anthropic.claudefordesktop"),
            ["tile-type": "small-spacer-tile", "tile-data": [String: Any]()],
            ["tile-type": "directory-tile", "tile-data": ["file-label": "Downloads"]]
        ]

        let decoded = codec.decode(raw)

        XCTAssertEqual(decoded.count, 2)
        guard case let .application(application) = decoded[0].content else {
            return XCTFail("Expected an application")
        }
        XCTAssertEqual(application.bundleIdentifier, "com.anthropic.claudefordesktop")
        XCTAssertEqual(application.lastKnownPath, "/Applications/Claude.app")
        XCTAssertEqual(decoded[1].content, .spacer(.compact))
    }

    func testApplyWritesResolvedItemsAndReportsMissingApps() throws {
        let preferences = FakeDockPreferences(items: [])
        let resolver = FakeResolver(pathsByKey: [
            "bundle:com.example.available": URL(fileURLWithPath: "/Applications/Available.app")
        ])
        let repository = DockRepository(preferences: preferences, resolver: resolver)
        let available = ApplicationReference(
            bundleIdentifier: "com.example.available",
            displayName: "Available",
            lastKnownPath: "/Moved/Available.app"
        )
        let missing = ApplicationReference(
            bundleIdentifier: "com.example.missing",
            displayName: "Missing",
            lastKnownPath: "/Applications/Missing.app"
        )

        let result = try repository.apply([
            .application(available),
            .spacer(.flexible),
            .application(missing)
        ])

        XCTAssertEqual(result.appliedItems.count, 2)
        XCTAssertEqual(result.missingApplications, [missing])
        XCTAssertEqual(preferences.restartCount, 1)
        XCTAssertEqual(repository.codec.decode(preferences.items).count, 2)
    }

    func testAllNativeSpacerKindsRoundTripInOrder() {
        let codec = DockCodec()
        let items = SpacerKind.allCases.map { DockItem.spacer($0) }

        let encoded = codec.encode(items, resolvingWith: FakeResolver(pathsByKey: [:]))
        let decoded = codec.decode(encoded.rawItems)

        XCTAssertEqual(decoded.map(\.content), items.map(\.content))
    }

    func testFailedVerificationRestoresPreviousDock() {
        let backup = [applicationTile(path: "/Applications/Backup.app", bundleIdentifier: "com.example.backup")]
        let preferences = FakeDockPreferences(items: backup)
        preferences.corruptNextReadAfterWrite = true
        let resolver = FakeResolver(pathsByKey: [
            "bundle:com.example.target": URL(fileURLWithPath: "/Applications/Target.app")
        ])
        let repository = DockRepository(preferences: preferences, resolver: resolver)
        let target = ApplicationReference(
            bundleIdentifier: "com.example.target",
            displayName: "Target",
            lastKnownPath: "/Applications/Target.app"
        )

        XCTAssertThrowsError(try repository.apply([.application(target)]))
        XCTAssertEqual(repository.codec.fingerprint(repository.codec.decode(preferences.items)),
                       repository.codec.fingerprint(repository.codec.decode(backup)))
        XCTAssertEqual(preferences.restartCount, 2)
        XCTAssertEqual(preferences.writeCount, 2)
    }

    func testSystemPreferencesAccessUsesAnIsolatedDomainAndPreservesOtherSections() throws {
        let domain = "fr.wiselaunch.DockMode.Tests.\(UUID().uuidString)"
        let appsKey = "persistent-apps"
        let othersKey = "persistent-others"
        let others: [[String: Any]] = [["tile-type": "directory-tile"]]
        let apps = [applicationTile(path: "/Applications/Test.app", bundleIdentifier: "com.example.test")]

        defer {
            CFPreferencesSetAppValue(appsKey as CFString, nil, domain as CFString)
            CFPreferencesSetAppValue(othersKey as CFString, nil, domain as CFString)
            CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }

        CFPreferencesSetAppValue(othersKey as CFString, others as CFPropertyList, domain as CFString)
        XCTAssertTrue(CFPreferencesSynchronize(
            domain as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ))

        let access = SystemDockPreferencesAccess(domain: domain, key: appsKey)
        try access.writePinnedItems(apps)

        let decodedApps = DockCodec().decode(try access.readPinnedItems())
        XCTAssertEqual(decodedApps.count, 1)
        let unchangedOthers = CFPreferencesCopyAppValue(othersKey as CFString, domain as CFString) as? [[String: Any]]
        XCTAssertEqual(unchangedOthers?.first?["tile-type"] as? String, "directory-tile")
    }

    private func applicationTile(path: String, bundleIdentifier: String) -> [String: Any] {
        [
            "GUID": 1,
            "tile-type": "file-tile",
            "tile-data": [
                "file-data": ["_CFURLString": path, "_CFURLStringType": 0],
                "file-label": URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                "file-type": 41,
                "bundle-identifier": bundleIdentifier
            ]
        ]
    }
}

private final class FakeResolver: ApplicationResolving {
    let pathsByKey: [String: URL]

    init(pathsByKey: [String: URL]) {
        self.pathsByKey = pathsByKey
    }

    func resolve(_ reference: ApplicationReference) -> URL? {
        pathsByKey[reference.stableKey]
    }
}

private final class FakeDockPreferences: DockPreferencesAccess {
    var items: [[String: Any]]
    var restartCount = 0
    var writeCount = 0
    var corruptNextReadAfterWrite = false
    private var shouldCorruptRead = false

    init(items: [[String: Any]]) {
        self.items = items
    }

    func readPinnedItems() throws -> [[String: Any]] {
        if shouldCorruptRead {
            shouldCorruptRead = false
            return []
        }
        return items
    }

    func writePinnedItems(_ items: [[String: Any]]) throws {
        self.items = items
        writeCount += 1
        if corruptNextReadAfterWrite && writeCount == 1 {
            shouldCorruptRead = true
        }
    }

    func restartDock() {
        restartCount += 1
    }
}
