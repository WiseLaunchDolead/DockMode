import DockModeCore
import XCTest

final class ModelsTests: XCTestCase {
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
}
