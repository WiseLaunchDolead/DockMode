import DockModeCore
import CoreFoundation
import Foundation

@main
struct DockModeCoreChecks {
    static func main() throws {
        var checks = CheckRunner()

        let existing = Profile(name: "Salarié", items: [])
        checks.expectThrows("empty profile names are rejected") {
            _ = try ProfileValidator.validateName("  ", excluding: nil, in: [existing])
        }
        checks.expectThrows("duplicate profile names ignore case") {
            _ = try ProfileValidator.validateName("SALARIÉ", excluding: nil, in: [existing])
        }

        let firstSpacer = DockItem.spacer(.compact)
        let secondSpacer = DockItem.spacer(.compact)
        let merged = DockItemIdentityMerger.merge(
            observed: [.spacer(.compact), .spacer(.compact)],
            preserving: [firstSpacer, secondSpacer]
        )
        checks.expect(
            merged.map(\.id) == [firstSpacer.id, secondSpacer.id],
            "spacer identities remain stable"
        )

        let draftApplication = ApplicationReference(
            bundleIdentifier: "example.draft",
            displayName: "Draft",
            lastKnownPath: "/Applications/Draft.app"
        )
        let draftItem = DockItem.application(draftApplication)
        var draft = DockLayoutDraft(savedItems: [draftItem])
        draft.addSpacer(.compact)
        draft.addSpacer(.regular)
        checks.expect(draft.isDirty, "Dock editor changes remain in a dirty draft")
        draft.discardChanges()
        checks.expect(
            !draft.isDirty && draft.items == [draftItem],
            "discarding a Dock draft restores its saved layout"
        )
        checks.expect(
            DockLayoutSavePolicy.action(profileID: UUID(), activeProfileID: UUID()) == .persistOnly,
            "an inactive Dock layout is saved without being applied"
        )
        let compactDraftSpacer = DockItem.spacer(.compact)
        let regularDraftSpacer = DockItem.spacer(.regular)
        var groupedDraft = DockLayoutDraft(
            savedItems: [draftItem, compactDraftSpacer, regularDraftSpacer]
        )
        _ = groupedDraft.move(
            ids: [draftItem.id, compactDraftSpacer.id],
            to: .end
        )
        checks.expect(
            groupedDraft.items.map(\.id)
                == [regularDraftSpacer.id, draftItem.id, compactDraftSpacer.id],
            "grouped Dock moves preserve selection order"
        )

        let codec = DockCodec()
        let rawItems = [
            applicationTile(path: "/Applications/Claude.app", bundleID: "com.anthropic.claudefordesktop"),
            ["tile-type": "small-spacer-tile", "tile-data": [String: Any]()],
            ["tile-type": "directory-tile", "tile-data": ["file-label": "Downloads"]]
        ]
        let decoded = codec.decode(rawItems)
        checks.expect(decoded.count == 2, "folders are excluded while apps and spacers are decoded")
        let allSpacers = SpacerKind.allCases.map { DockItem.spacer($0) }
        let spacerRoundTrip = codec.decode(
            codec.encode(allSpacers, resolvingWith: StaticResolver(pathsByKey: [:])).rawItems
        )
        checks.expect(
            spacerRoundTrip.map(\.content) == allSpacers.map(\.content),
            "all native spacer types round-trip in order"
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockModeChecks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let profileStore = ProfileStore(baseDirectory: directory)
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let storedProfile = Profile(
            name: "Freelance",
            color: .purple,
            items: decoded,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        let document = ProfilesDocument(profiles: [storedProfile], activeProfileID: storedProfile.id)
        try profileStore.save(document)
        try checks.expect(try profileStore.load() == document, "profile storage round-trips atomically")

        let backup = [applicationTile(path: "/Applications/Backup.app", bundleID: "example.backup")]
        let preferences = InMemoryDockPreferences(items: backup)
        preferences.corruptNextReadAfterWrite = true
        let resolver = StaticResolver(pathsByKey: [
            "bundle:example.target": URL(fileURLWithPath: "/Applications/Target.app")
        ])
        let repository = DockRepository(preferences: preferences, resolver: resolver)
        let target = ApplicationReference(
            bundleIdentifier: "example.target",
            displayName: "Target",
            lastKnownPath: "/Applications/Target.app"
        )
        checks.expectThrows("failed verification restores the previous Dock") {
            _ = try repository.apply([.application(target)])
        }
        checks.expect(
            codec.fingerprint(codec.decode(preferences.items)) == codec.fingerprint(codec.decode(backup)),
            "rollback restores the original pinned applications"
        )

        let isolatedDomain = "fr.wiselaunch.DockMode.Checks.\(UUID().uuidString)"
        let appsKey = "persistent-apps"
        let othersKey = "persistent-others"
        defer {
            CFPreferencesSetAppValue(appsKey as CFString, nil, isolatedDomain as CFString)
            CFPreferencesSetAppValue(othersKey as CFString, nil, isolatedDomain as CFString)
            CFPreferencesSynchronize(
                isolatedDomain as CFString,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
        }
        CFPreferencesSetAppValue(
            othersKey as CFString,
            [["tile-type": "directory-tile"]] as CFPropertyList,
            isolatedDomain as CFString
        )
        _ = CFPreferencesSynchronize(
            isolatedDomain as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        let isolatedPreferences = SystemDockPreferencesAccess(domain: isolatedDomain, key: appsKey)
        try isolatedPreferences.writePinnedItems(rawItems)
        let isolatedOthers = CFPreferencesCopyAppValue(
            othersKey as CFString,
            isolatedDomain as CFString
        ) as? [[String: Any]]
        try checks.expect(
            codec.decode(try isolatedPreferences.readPinnedItems()).count == 2,
            "CFPreferences access works in an isolated domain"
        )
        checks.expect(
            isolatedOthers?.first?["tile-type"] as? String == "directory-tile",
            "writing pinned apps preserves other Dock sections"
        )

        let originalProfileID = UUID()
        let firstFocusProfileID = UUID()
        let secondFocusProfileID = UUID()
        var focusState = FocusAutomationState()
        _ = FocusAutomationReducer.apply(
            FocusActivationRequest(action: .activate(profileID: firstFocusProfileID)),
            to: &focusState,
            currentActiveProfileID: originalProfileID
        )
        let secondFocusTarget = FocusAutomationReducer.apply(
            FocusActivationRequest(action: .activate(profileID: secondFocusProfileID)),
            to: &focusState,
            currentActiveProfileID: firstFocusProfileID
        )
        checks.expect(
            secondFocusTarget == secondFocusProfileID
                && focusState.profileBeforeFocusID == originalProfileID,
            "direct Focus transitions preserve the original profile"
        )
        let restoredProfile = FocusAutomationReducer.apply(
            FocusActivationRequest(action: .deactivate),
            to: &focusState,
            currentActiveProfileID: secondFocusProfileID
        )
        checks.expect(
            restoredProfile == originalProfileID && !focusState.isActive,
            "Focus deactivation restores the previous profile"
        )

        try checks.finish()
    }

    private static func applicationTile(path: String, bundleID: String) -> [String: Any] {
        [
            "GUID": 1,
            "tile-type": "file-tile",
            "tile-data": [
                "file-data": ["_CFURLString": path, "_CFURLStringType": 0],
                "file-label": URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                "file-type": 41,
                "bundle-identifier": bundleID
            ]
        ]
    }
}

private struct CheckRunner {
    private var failures: [String] = []
    private var successes = 0

    mutating func expect(_ condition: @autoclosure () throws -> Bool, _ label: String) rethrows {
        if try condition() {
            successes += 1
            print("✓ \(label)")
        } else {
            failures.append(label)
            print("✗ \(label)")
        }
    }

    mutating func expectThrows(_ label: String, operation: () throws -> Void) {
        do {
            try operation()
            failures.append(label)
            print("✗ \(label)")
        } catch {
            successes += 1
            print("✓ \(label)")
        }
    }

    func finish() throws {
        guard failures.isEmpty else {
            throw CheckFailure(failures: failures)
        }
        print("\n\(successes) core checks passed")
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    let failures: [String]
    var description: String { "Failed checks: \(failures.joined(separator: ", "))" }
}

private final class StaticResolver: ApplicationResolving {
    let pathsByKey: [String: URL]

    init(pathsByKey: [String: URL]) {
        self.pathsByKey = pathsByKey
    }

    func resolve(_ reference: ApplicationReference) -> URL? {
        pathsByKey[reference.stableKey]
    }
}

private final class InMemoryDockPreferences: DockPreferencesAccess {
    var items: [[String: Any]]
    var corruptNextReadAfterWrite = false
    private var writeCount = 0
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

    func restartDock() {}
}
