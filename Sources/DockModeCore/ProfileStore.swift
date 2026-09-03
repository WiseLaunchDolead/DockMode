import Foundation

public struct ProfileStore: Sendable {
    public let documentURL: URL

    public init(baseDirectory: URL = DockModeStorage.sharedContainerURL()) {
        documentURL = baseDirectory.appendingPathComponent(DockModeConstants.profileDocumentName)
    }

    public func load() throws -> ProfilesDocument {
        guard FileManager.default.fileExists(atPath: documentURL.path) else {
            return ProfilesDocument()
        }

        let data = try Data(contentsOf: documentURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let document = try decoder.decode(ProfilesDocument.self, from: data)
        guard document.schemaVersion <= DockModeConstants.schemaVersion else {
            throw ProfileStoreError.unsupportedSchema(document.schemaVersion)
        }
        return document
    }

    public func save(_ document: ProfilesDocument) throws {
        try FileManager.default.createDirectory(
            at: documentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(document)
        try data.write(to: documentURL, options: [.atomic])
    }
}

public enum ProfileStoreError: Error, LocalizedError, Equatable {
    case unsupportedSchema(Int)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            String(
                format: NSLocalizedString(
                    "This profile file was created by a newer DockMode schema (%d).",
                    bundle: .main,
                    comment: "Unsupported profile storage format"
                ),
                version
            )
        }
    }
}
