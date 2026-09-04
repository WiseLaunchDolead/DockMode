import DockModeCore
import XCTest

final class ModelsTests: XCTestCase {
    private let mail = ApplicationReference(
        bundleIdentifier: "com.apple.mail",
        displayName: "Mail",
        lastKnownPath: "/System/Applications/Mail.app"
    )
    private let calendar = ApplicationReference(
        bundleIdentifier: "com.apple.iCal",
        displayName: "Calendar",
        lastKnownPath: "/System/Applications/Calendar.app"
    )

    func testProfileNameMustBePresentAndUnique() throws {
        let existing = Profile(name: "Salarié", items: [])

        XCTAssertThrowsError(try ProfileValidator.validateName("   ", excluding: nil, in: [existing])) {
            XCTAssertEqual($0 as? ProfileValidationError, .emptyName)
        }
        XCTAssertThrowsError(try ProfileValidator.validateName("SALARIÉ", excluding: nil, in: [existing])) {
            XCTAssertEqual($0 as? ProfileValidationError, .duplicateName)
        }
        XCTAssertEqual(
            try ProfileValidator.validateName("  Freelance  ", excluding: nil, in: [existing]),
            "Freelance"
        )
        XCTAssertEqual(
            try ProfileValidator.validateName("Salarié", excluding: existing.id, in: [existing]),
            "Salarié"
        )
    }

    func testIdentityMergerPreservesDuplicateSpacerIdentifiersInOrder() {
        let firstSpacer = DockItem.spacer(.compact)
        let secondSpacer = DockItem.spacer(.compact)
        let existing = [firstSpacer, secondSpacer]
        let observed = [DockItem.spacer(.compact), DockItem.spacer(.compact)]

        let merged = DockItemIdentityMerger.merge(observed: observed, preserving: existing)

        XCTAssertEqual(merged.map(\.id), [firstSpacer.id, secondSpacer.id])
    }

    func testReconcilerKeepsMissingApplicationAtItsPreviousPosition() {
        let safari = ApplicationReference(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            lastKnownPath: "/Applications/Safari.app"
        )
        let missing = ApplicationReference(
            bundleIdentifier: "example.missing",
            displayName: "Missing",
            lastKnownPath: "/Applications/Missing.app"
        )
        let existing = [DockItem.application(safari), DockItem.application(missing), .spacer(.regular)]
        let observed = [DockItem.application(safari), .spacer(.regular)]

        let reconciled = DockItemReconciler.reconcile(
            observed: observed,
            preservingMissingFrom: existing,
            missingApplicationKeys: [missing.stableKey]
        )

        XCTAssertEqual(reconciled.map(\.matchingKey), existing.map(\.matchingKey))
        XCTAssertEqual(reconciled[1].id, existing[1].id)
    }

    func testProfileColorClampsComponents() {
        let color = ProfileColor(red: -1, green: 0.5, blue: 2, alpha: 4)
        XCTAssertEqual(color.red, 0)
        XCTAssertEqual(color.green, 0.5)
        XCTAssertEqual(color.blue, 1)
        XCTAssertEqual(color.alpha, 1)
    }

    func testFocusTransitionsPreserveTheOriginalProfileAcrossDirectSwitches() {
        let original = UUID()
        let work = UUID()
        let personal = UUID()
        var state = FocusAutomationState()

        XCTAssertEqual(
            FocusAutomationReducer.apply(
                FocusActivationRequest(action: .activate(profileID: work)),
                to: &state,
                currentActiveProfileID: original
            ),
            work
        )
        XCTAssertEqual(state.profileBeforeFocusID, original)

        XCTAssertEqual(
            FocusAutomationReducer.apply(
                FocusActivationRequest(action: .activate(profileID: personal)),
                to: &state,
                currentActiveProfileID: work
            ),
            personal
        )
        XCTAssertEqual(state.profileBeforeFocusID, original)

        XCTAssertEqual(
            FocusAutomationReducer.apply(
                FocusActivationRequest(action: .deactivate),
                to: &state,
                currentActiveProfileID: personal
            ),
            original
        )
        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.profileBeforeFocusID)
    }

    func testManualProfileChoiceDoesNotMutateFocusState() {
        let original = UUID()
        let focusProfile = UUID()
        var state = FocusAutomationState()
        _ = FocusAutomationReducer.apply(
            FocusActivationRequest(action: .activate(profileID: focusProfile)),
            to: &state,
            currentActiveProfileID: original
        )

        // Manual profile switching does not call the reducer. The original profile
        // therefore remains the restoration target until the next Focus event.
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.profileBeforeFocusID, original)
    }

    func testDockLayoutDraftDirtyStateAndDiscard() {
        let initial = [DockItem.application(mail)]
        var draft = DockLayoutDraft(savedItems: initial)

        XCTAssertFalse(draft.isDirty)
        draft.addSpacer(.compact)
        XCTAssertTrue(draft.isDirty)

        draft.discardChanges()
        XCTAssertFalse(draft.isDirty)
        XCTAssertEqual(draft.items, initial)
    }

    func testDockLayoutDraftRejectsDuplicateApplications() {
        var draft = DockLayoutDraft(savedItems: [.application(mail)])

        XCTAssertFalse(draft.addApplication(mail))
        XCTAssertTrue(draft.addApplication(calendar))
        XCTAssertEqual(draft.items.count, 2)
    }

    func testDockLayoutDraftAddsSmallAndRegularSpacers() {
        var draft = DockLayoutDraft(savedItems: [])

        draft.addSpacer(.compact)
        draft.addSpacer(.regular)

        XCTAssertEqual(draft.items.map(\.content), [.spacer(.compact), .spacer(.regular)])
    }

    func testDockPreviewFitsACommonTwelveItemLayoutInACompactWindow() {
        let applications = (0..<10).map { index in
            DockItem.application(
                ApplicationReference(
                    bundleIdentifier: "test.application.\(index)",
                    displayName: "Application \(index)",
                    lastKnownPath: "/Applications/Application \(index).app"
                )
            )
        }
        let items = Array(applications.prefix(5))
            + [.spacer(.compact)]
            + Array(applications.suffix(5))
            + [.spacer(.regular)]

        let metrics = DockPreviewLayoutCalculator.metrics(for: items, availableWidth: 659)

        XCTAssertLessThanOrEqual(metrics.contentWidth, 659)
        XCTAssertTrue(metrics.fitsWithoutScrolling)
        XCTAssertGreaterThan(metrics.iconSize, DockPreviewLayoutCalculator.minimumIconSize)
        XCTAssertLessThan(metrics.iconSize, DockPreviewLayoutCalculator.maximumIconSize)
    }

    func testDockPreviewUsesFullSizeWhenThereIsEnoughRoom() {
        let items = [DockItem.application(mail), DockItem.spacer(.regular), DockItem.application(calendar)]

        let metrics = DockPreviewLayoutCalculator.metrics(for: items, availableWidth: 900)

        XCTAssertEqual(metrics.iconSize, DockPreviewLayoutCalculator.maximumIconSize)
        XCTAssertTrue(metrics.fitsWithoutScrolling)
    }

    func testDockPreviewKeepsVeryLongLayoutsScrollableAtTheMinimumSize() {
        let items = (0..<24).map { index in
            DockItem.application(
                ApplicationReference(
                    bundleIdentifier: "test.long-layout.\(index)",
                    displayName: "Application \(index)",
                    lastKnownPath: "/Applications/Application \(index).app"
                )
            )
        }

        let metrics = DockPreviewLayoutCalculator.metrics(for: items, availableWidth: 659)

        XCTAssertEqual(metrics.iconSize, DockPreviewLayoutCalculator.minimumIconSize)
        XCTAssertGreaterThan(metrics.contentWidth, 659)
        XCTAssertFalse(metrics.fitsWithoutScrolling)
    }

    func testDockLayoutDraftMoveAndRemoveOperations() {
        let first = DockItem.application(mail)
        let spacer = DockItem.spacer(.regular)
        let last = DockItem.application(calendar)
        var draft = DockLayoutDraft(savedItems: [first, spacer, last])

        XCTAssertFalse(draft.move(id: first.id, direction: .left))
        XCTAssertTrue(draft.move(id: last.id, before: first.id))
        XCTAssertEqual(draft.items.map(\.id), [last.id, first.id, spacer.id])
        XCTAssertTrue(draft.move(id: first.id, direction: .right))
        XCTAssertFalse(draft.move(id: first.id, direction: .right))
        XCTAssertTrue(draft.remove(id: first.id))
        XCTAssertEqual(draft.items.map(\.id), [last.id, spacer.id])
    }

    func testDockLayoutDraftReordersAcrossAdjacentItems() {
        let first = DockItem.application(mail)
        let second = DockItem.spacer(.compact)
        let third = DockItem.application(calendar)
        var draft = DockLayoutDraft(savedItems: [first, second, third])

        XCTAssertTrue(draft.reorder(id: first.id, toPositionOf: second.id))
        XCTAssertEqual(draft.items.map(\.id), [second.id, first.id, third.id])
        XCTAssertTrue(draft.reorder(id: third.id, toPositionOf: second.id))
        XCTAssertEqual(draft.items.map(\.id), [third.id, second.id, first.id])
    }

    func testDockLayoutDraftMovesContiguousSelectionToEnd() {
        let first = DockItem.application(mail)
        let compact = DockItem.spacer(.compact)
        let second = DockItem.application(calendar)
        let regular = DockItem.spacer(.regular)
        var draft = DockLayoutDraft(savedItems: [first, compact, second, regular])

        XCTAssertTrue(draft.move(ids: [compact.id, second.id], to: .end))
        XCTAssertEqual(draft.items.map(\.id), [first.id, regular.id, compact.id, second.id])
    }

    func testDockLayoutDraftMovesNonContiguousSelectionAndPreservesLayoutOrder() {
        let first = DockItem.application(mail)
        let compact = DockItem.spacer(.compact)
        let second = DockItem.application(calendar)
        let regular = DockItem.spacer(.regular)
        let last = DockItem.spacer(.flexible)
        var draft = DockLayoutDraft(savedItems: [first, compact, second, regular, last])

        XCTAssertTrue(draft.move(ids: [second.id, first.id], to: .after(regular.id)))
        XCTAssertEqual(
            draft.items.map(\.id),
            [compact.id, regular.id, first.id, second.id, last.id]
        )
    }

    func testDockLayoutDraftMovesSelectionToBeginning() {
        let first = DockItem.application(mail)
        let compact = DockItem.spacer(.compact)
        let second = DockItem.application(calendar)
        let regular = DockItem.spacer(.regular)
        var draft = DockLayoutDraft(savedItems: [first, compact, second, regular])

        XCTAssertTrue(draft.move(ids: [regular.id, second.id], to: .before(first.id)))
        XCTAssertEqual(draft.items.map(\.id), [second.id, regular.id, first.id, compact.id])
    }

    func testDockLayoutDraftTreatsDropsInsideSelectionAndUnknownIDsAsNoOps() {
        let first = DockItem.application(mail)
        let compact = DockItem.spacer(.compact)
        let second = DockItem.application(calendar)
        var draft = DockLayoutDraft(savedItems: [first, compact, second])

        XCTAssertFalse(draft.move(ids: [compact.id, second.id], to: .before(second.id)))
        XCTAssertFalse(draft.move(ids: [UUID()], to: .end))
        XCTAssertFalse(draft.move(ids: [first.id], to: .before(UUID())))
        XCTAssertEqual(draft.items.map(\.id), [first.id, compact.id, second.id])
    }

    func testDockLayoutDraftRemovesMixedSelectionAtomically() {
        let first = DockItem.application(mail)
        let compact = DockItem.spacer(.compact)
        let second = DockItem.application(calendar)
        var draft = DockLayoutDraft(savedItems: [first, compact, second])

        XCTAssertTrue(draft.remove(ids: [first.id, compact.id]))
        XCTAssertEqual(draft.items.map(\.id), [second.id])
        XCTAssertFalse(draft.remove(ids: [UUID()]))
    }

    func testDockLayoutDraftSynchronizesSavedChangesWithoutOverwritingEdits() {
        let first = DockItem.application(mail)
        let refreshed = [DockItem.application(calendar)]
        var dirty = DockLayoutDraft(savedItems: [first])
        dirty.addSpacer(.regular)

        dirty.synchronize(with: refreshed)
        XCTAssertTrue(dirty.isDirty)
        XCTAssertEqual(dirty.items.first?.id, first.id)
        XCTAssertEqual(dirty.savedItems, refreshed)

        var clean = DockLayoutDraft(savedItems: [first])
        clean.synchronize(with: refreshed)
        XCTAssertFalse(clean.isDirty)
        XCTAssertEqual(clean.items, refreshed)
    }

    func testDockLayoutDraftReplaceKeepsItemIdentity() {
        let item = DockItem.application(mail)
        var draft = DockLayoutDraft(savedItems: [item])

        XCTAssertTrue(draft.replace(id: item.id, with: .application(calendar)))
        XCTAssertEqual(draft.items.first?.id, item.id)
        XCTAssertEqual(draft.items.first?.content, .application(calendar))
    }

    func testDockLayoutSavePolicyOnlyAppliesTheActiveProfile() {
        let activeID = UUID()

        XCTAssertEqual(
            DockLayoutSavePolicy.action(profileID: activeID, activeProfileID: activeID),
            .applyToDock
        )
        XCTAssertEqual(
            DockLayoutSavePolicy.action(profileID: UUID(), activeProfileID: activeID),
            .persistOnly
        )
    }

    func testUnsavedDraftChoicesProduceTheExpectedEffects() {
        XCTAssertEqual(UnsavedDraftPolicy.effect(for: .save), .saveAndContinue)
        XCTAssertEqual(UnsavedDraftPolicy.effect(for: .discard), .discardAndContinue)
        XCTAssertEqual(UnsavedDraftPolicy.effect(for: .cancel), .stay)
    }
}
