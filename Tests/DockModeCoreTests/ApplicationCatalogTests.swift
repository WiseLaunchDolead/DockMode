import DockModeCore
import Foundation
import XCTest

final class ApplicationCatalogTests: XCTestCase {
    func testDiscoveryStopsAtApplicationBundles() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let outer = root.appendingPathComponent("Outer.app", isDirectory: true)
        let inner = outer.appendingPathComponent("Contents/Helpers/Inner.app", isDirectory: true)
        try createBundle(at: outer, identifier: "com.example.outer", name: "Outer")
        try createBundle(at: inner, identifier: "com.example.inner", name: "Inner")

        let applications = ApplicationCatalog.discover(roots: [root])

        XCTAssertEqual(applications.count, 1)
        XCTAssertEqual(applications.first?.bundleIdentifier, "com.example.outer")
        XCTAssertEqual(applications.first?.displayName, "Outer")
    }

    func testWorkspaceResolverUsesTheKnownPathWhenItsBundleMatches() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Available.app", isDirectory: true)
        try createBundle(at: app, identifier: "com.example.available", name: "Available")
        let reference = ApplicationReference(
            bundleIdentifier: "com.example.available",
            displayName: "Available",
            lastKnownPath: app.path
        )

        let resolved = WorkspaceApplicationResolver().resolve(reference)

        XCTAssertEqual(resolved?.standardizedFileURL.path, app.standardizedFileURL.path)
    }

    private func createBundle(at url: URL, identifier: String, name: String) throws {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": identifier,
            "CFBundleName": name,
            "CFBundlePackageType": "APPL"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
