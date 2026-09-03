import AppIntents
import DockModeCore
import Foundation
import OSLog

struct DockModeFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Switch Dock profile"
    static let description: IntentDescription? = "Choose the DockMode profile to use with this Focus."

    @Parameter(title: "Profile")
    var profile: DockModeProfileEntity?

    var displayRepresentation: DisplayRepresentation {
        if let profile {
            DisplayRepresentation(title: "Dock: \(profile.name)")
        } else {
            DisplayRepresentation(title: "Restore previous Dock")
        }
    }

    var appContext: FocusFilterAppContext {
        FocusFilterAppContext(notificationFilterPredicate: NSPredicate(value: true))
    }

    static func suggestedFocusFilters(for context: FocusFilterSuggestionContext) async -> [DockModeFocusFilter] {
        guard let firstProfile = try? await DockModeProfileQuery().suggestedEntities().first else {
            return []
        }
        let filter = DockModeFocusFilter()
        filter.profile = firstProfile
        return [filter]
    }

    func perform() async throws -> some IntentResult {
        let action: FocusActivationAction
        if let profile {
            action = .activate(profileID: profile.id)
        } else {
            action = .deactivate
        }

        let store = FocusRequestStore()
        try store.save(FocusActivationRequest(action: action))
        store.postDarwinNotification()

        Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "fr.wiselaunch.DockMode.FocusExtension",
            category: "FocusFilter"
        ).info("Published a Focus activation request")
        return .result()
    }
}
