import CoreFoundation
import Foundation

public struct FocusRequestStore: Sendable {
    public let requestURL: URL

    public init(baseDirectory: URL = DockModeStorage.sharedContainerURL()) {
        requestURL = baseDirectory.appendingPathComponent(DockModeConstants.focusRequestName)
    }

    public func load() throws -> FocusActivationRequest? {
        guard FileManager.default.fileExists(atPath: requestURL.path) else { return nil }
        let data = try Data(contentsOf: requestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(FocusActivationRequest.self, from: data)
    }

    public func save(_ request: FocusActivationRequest) throws {
        try FileManager.default.createDirectory(
            at: requestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(request)
        try data.write(to: requestURL, options: [.atomic])
    }

    public func postDarwinNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(DockModeConstants.focusNotificationName as CFString),
            nil,
            nil,
            true
        )
    }
}
