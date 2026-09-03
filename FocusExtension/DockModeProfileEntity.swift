import AppIntents
import DockModeCore
import Foundation

struct DockModeProfileEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "DockMode Profile")
    static let defaultQuery = DockModeProfileQuery()

    let id: UUID
    let name: String

    init(profile: Profile) {
        id = profile.id
        name = profile.name
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: "rectangle.3.group")
        )
    }
}

struct DockModeProfileQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [DockModeProfileEntity] {
        let profiles = try ProfileStore().load().profiles
        return profiles
            .filter { identifiers.contains($0.id) }
            .map(DockModeProfileEntity.init)
    }

    func suggestedEntities() async throws -> [DockModeProfileEntity] {
        try ProfileStore().load().profiles.map(DockModeProfileEntity.init)
    }
}
