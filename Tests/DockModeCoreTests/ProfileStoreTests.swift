import DockModeCore
import Foundation
import XCTest

final class ProfileStoreTests: XCTestCase {
    func testRoundTripPersistsProfilesAndFocusState() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(baseDirectory: directory)
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let profile = Profile(
            name: "Freelance",
            color: .purple,
            items: [.spacer(.compact)],
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        let document = ProfilesDocument(
            profiles: [profile],
            activeProfileID: profile.id,
            focusState: FocusAutomationState(
                isActive: true,
                profileBeforeFocusID: profile.id,
                lastHandledRequestID: UUID()
            )
        )

        try store.save(document)

        XCTAssertEqual(try store.load(), document)
    }

    func testMissingStoreReturnsEmptyDocument() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let document = try ProfileStore(baseDirectory: directory).load()

        XCTAssertTrue(document.profiles.isEmpty)
        XCTAssertNil(document.activeProfileID)
    }

    func testFutureSchemaIsRejected() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(baseDirectory: directory)
        try store.save(ProfilesDocument(schemaVersion: DockModeConstants.schemaVersion + 1))

        XCTAssertThrowsError(try store.load()) {
            XCTAssertEqual($0 as? ProfileStoreError, .unsupportedSchema(DockModeConstants.schemaVersion + 1))
        }
    }

    func testFocusRequestRoundTrip() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FocusRequestStore(baseDirectory: directory)
        let request = FocusActivationRequest(
            action: .activate(profileID: UUID()),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try store.save(request)

        XCTAssertEqual(try store.load(), request)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
