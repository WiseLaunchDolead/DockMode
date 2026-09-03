import Foundation

public struct ProfileColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red.clamped(to: 0...1)
        self.green = green.clamped(to: 0...1)
        self.blue = blue.clamped(to: 0...1)
        self.alpha = alpha.clamped(to: 0...1)
    }

    public static let blue = ProfileColor(red: 0.14, green: 0.39, blue: 0.98)
    public static let purple = ProfileColor(red: 0.49, green: 0.25, blue: 0.92)
    public static let pink = ProfileColor(red: 0.91, green: 0.24, blue: 0.52)
    public static let red = ProfileColor(red: 0.91, green: 0.20, blue: 0.20)
    public static let orange = ProfileColor(red: 0.96, green: 0.48, blue: 0.10)
    public static let yellow = ProfileColor(red: 0.92, green: 0.69, blue: 0.08)
    public static let green = ProfileColor(red: 0.16, green: 0.67, blue: 0.38)
    public static let teal = ProfileColor(red: 0.06, green: 0.62, blue: 0.65)

    public static let palette: [ProfileColor] = [
        .blue, .purple, .pink, .red, .orange, .yellow, .green, .teal
    ]
}

public enum SpacerKind: String, Codable, CaseIterable, Hashable, Sendable {
    case compact
    case regular
    case flexible

    public var dockTileType: String {
        switch self {
        case .compact: "small-spacer-tile"
        case .regular: "spacer-tile"
        case .flexible: "flex-spacer-tile"
        }
    }

    public init?(dockTileType: String) {
        switch dockTileType {
        case "small-spacer-tile": self = .compact
        case "spacer-tile": self = .regular
        case "flex-spacer-tile": self = .flexible
        default: return nil
        }
    }
}

public struct ApplicationReference: Codable, Hashable, Sendable {
    public var bundleIdentifier: String?
    public var displayName: String
    public var lastKnownPath: String

    public init(bundleIdentifier: String?, displayName: String, lastKnownPath: String) {
        self.bundleIdentifier = bundleIdentifier?.nilIfEmpty
        self.displayName = displayName
        self.lastKnownPath = lastKnownPath
    }

    public var stableKey: String {
        if let bundleIdentifier {
            return "bundle:\(bundleIdentifier.lowercased())"
        }
        return "path:\(URL(fileURLWithPath: lastKnownPath).standardizedFileURL.path)"
    }
}

public enum DockItemContent: Codable, Hashable, Sendable {
    case application(ApplicationReference)
    case spacer(SpacerKind)
}

public struct DockItem: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var content: DockItemContent

    public init(id: UUID = UUID(), content: DockItemContent) {
        self.id = id
        self.content = content
    }

    public static func application(_ reference: ApplicationReference, id: UUID = UUID()) -> DockItem {
        DockItem(id: id, content: .application(reference))
    }

    public static func spacer(_ kind: SpacerKind, id: UUID = UUID()) -> DockItem {
        DockItem(id: id, content: .spacer(kind))
    }

    public var matchingKey: String {
        switch content {
        case let .application(reference): "application:\(reference.stableKey)"
        case let .spacer(kind): "spacer:\(kind.rawValue)"
        }
    }
}

public struct Profile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var color: ProfileColor
    public var items: [DockItem]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        color: ProfileColor = .blue,
        items: [DockItem],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.color = color
        self.items = items
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct FocusAutomationState: Codable, Hashable, Sendable {
    public var isActive: Bool
    public var profileBeforeFocusID: UUID?
    public var lastHandledRequestID: UUID?

    public init(
        isActive: Bool = false,
        profileBeforeFocusID: UUID? = nil,
        lastHandledRequestID: UUID? = nil
    ) {
        self.isActive = isActive
        self.profileBeforeFocusID = profileBeforeFocusID
        self.lastHandledRequestID = lastHandledRequestID
    }
}

public struct ProfilesDocument: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var profiles: [Profile]
    public var activeProfileID: UUID?
    public var focusState: FocusAutomationState

    public init(
        schemaVersion: Int = DockModeConstants.schemaVersion,
        profiles: [Profile] = [],
        activeProfileID: UUID? = nil,
        focusState: FocusAutomationState = FocusAutomationState()
    ) {
        self.schemaVersion = schemaVersion
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.focusState = focusState
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, profiles, activeProfileID, focusState
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        profiles = try container.decodeIfPresent([Profile].self, forKey: .profiles) ?? []
        activeProfileID = try container.decodeIfPresent(UUID.self, forKey: .activeProfileID)
        focusState = try container.decodeIfPresent(FocusAutomationState.self, forKey: .focusState)
            ?? FocusAutomationState()
    }
}

public enum FocusActivationAction: Codable, Hashable, Sendable {
    case activate(profileID: UUID)
    case deactivate
}

public struct FocusActivationRequest: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var action: FocusActivationAction
    public var createdAt: Date

    public init(id: UUID = UUID(), action: FocusActivationAction, createdAt: Date = Date()) {
        self.id = id
        self.action = action
        self.createdAt = createdAt
    }
}

public enum FocusAutomationReducer {
    @discardableResult
    public static func apply(
        _ request: FocusActivationRequest,
        to state: inout FocusAutomationState,
        currentActiveProfileID: UUID?
    ) -> UUID? {
        state.lastHandledRequestID = request.id

        switch request.action {
        case let .activate(profileID):
            if !state.isActive {
                state.profileBeforeFocusID = currentActiveProfileID
            }
            state.isActive = true
            return profileID

        case .deactivate:
            let profileToRestore = state.profileBeforeFocusID
            state.isActive = false
            state.profileBeforeFocusID = nil
            return profileToRestore
        }
    }
}

public enum FocusAutomationError: Error, LocalizedError {
    case profileUnavailable

    public var errorDescription: String? {
        NSLocalizedString(
            "The profile selected by the Focus filter is no longer available.",
            bundle: .main,
            comment: "Focus filter references a deleted profile"
        )
    }
}

public enum ProfileValidationError: Error, Equatable, LocalizedError {
    case emptyName
    case duplicateName

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            NSLocalizedString("A profile name is required.", bundle: .main, comment: "Profile validation error")
        case .duplicateName:
            NSLocalizedString("A profile with this name already exists.", bundle: .main, comment: "Profile validation error")
        }
    }
}

public enum ProfileValidator {
    public static func normalizedName(_ name: String) throws -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw ProfileValidationError.emptyName }
        return normalized
    }

    public static func validateName(_ name: String, excluding profileID: UUID?, in profiles: [Profile]) throws -> String {
        let normalized = try normalizedName(name)
        let isDuplicate = profiles.contains { profile in
            profile.id != profileID && profile.name.compare(normalized, options: [.caseInsensitive]) == .orderedSame
        }
        guard !isDuplicate else { throw ProfileValidationError.duplicateName }
        return normalized
    }
}

public enum DockItemIdentityMerger {
    public static func merge(observed: [DockItem], preserving existing: [DockItem]) -> [DockItem] {
        var identifiersByKey: [String: [UUID]] = [:]
        for item in existing {
            identifiersByKey[item.matchingKey, default: []].append(item.id)
        }

        return observed.map { item in
            var item = item
            if var identifiers = identifiersByKey[item.matchingKey], !identifiers.isEmpty {
                item.id = identifiers.removeFirst()
                identifiersByKey[item.matchingKey] = identifiers
            }
            return item
        }
    }
}

public enum DockItemReconciler {
    public static func reconcile(
        observed: [DockItem],
        preservingMissingFrom existing: [DockItem],
        missingApplicationKeys: Set<String>
    ) -> [DockItem] {
        var result = DockItemIdentityMerger.merge(observed: observed, preserving: existing)
        for (index, item) in existing.enumerated() {
            guard case let .application(reference) = item.content,
                  missingApplicationKeys.contains(reference.stableKey),
                  !result.contains(where: { $0.matchingKey == item.matchingKey }) else {
                continue
            }
            result.insert(item, at: min(index, result.count))
        }
        return result
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
