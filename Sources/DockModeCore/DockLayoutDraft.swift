import Foundation

public enum DockMoveDirection: Sendable {
    case left
    case right
}

public enum DockInsertionTarget: Equatable, Sendable {
    case before(UUID)
    case after(UUID)
    case end
}

public enum DockLayoutSaveAction: Equatable, Sendable {
    case applyToDock
    case persistOnly
}

public enum DockLayoutSavePolicy {
    public static func action(profileID: UUID, activeProfileID: UUID?) -> DockLayoutSaveAction {
        profileID == activeProfileID ? .applyToDock : .persistOnly
    }
}

public enum UnsavedDraftChoice: Sendable {
    case save
    case discard
    case cancel
}

public enum UnsavedDraftEffect: Equatable, Sendable {
    case saveAndContinue
    case discardAndContinue
    case stay
}

public enum UnsavedDraftPolicy {
    public static func effect(for choice: UnsavedDraftChoice) -> UnsavedDraftEffect {
        switch choice {
        case .save: .saveAndContinue
        case .discard: .discardAndContinue
        case .cancel: .stay
        }
    }
}

public struct DockLayoutDraft: Equatable, Sendable {
    public private(set) var savedItems: [DockItem]
    public private(set) var items: [DockItem]

    public init(savedItems: [DockItem]) {
        self.savedItems = savedItems
        items = savedItems
    }

    public var isDirty: Bool {
        items != savedItems
    }

    @discardableResult
    public mutating func addApplication(_ application: ApplicationReference) -> Bool {
        guard !items.contains(where: { item in
            guard case let .application(reference) = item.content else { return false }
            return reference.stableKey == application.stableKey
        }) else {
            return false
        }

        items.append(.application(application))
        return true
    }

    public mutating func addSpacer(_ kind: SpacerKind) {
        items.append(.spacer(kind))
    }

    @discardableResult
    public mutating func remove(id: UUID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        items.remove(at: index)
        return true
    }

    @discardableResult
    public mutating func remove(ids: Set<UUID>) -> Bool {
        guard !ids.isEmpty else { return false }
        let previousCount = items.count
        items.removeAll(where: { ids.contains($0.id) })
        return items.count != previousCount
    }

    @discardableResult
    public mutating func move(id: UUID, direction: DockMoveDirection) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        let destination: Int
        switch direction {
        case .left:
            destination = index - 1
        case .right:
            destination = index + 1
        }
        guard items.indices.contains(destination) else { return false }
        items.swapAt(index, destination)
        return true
    }

    @discardableResult
    public mutating func move(id: UUID, before destinationID: UUID) -> Bool {
        guard id != destinationID,
              let sourceIndex = items.firstIndex(where: { $0.id == id }),
              let destinationIndex = items.firstIndex(where: { $0.id == destinationID }) else {
            return false
        }

        let item = items.remove(at: sourceIndex)
        let adjustedDestination = sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex
        items.insert(item, at: adjustedDestination)
        return true
    }

    @discardableResult
    public mutating func reorder(id: UUID, toPositionOf destinationID: UUID) -> Bool {
        guard id != destinationID,
              let sourceIndex = items.firstIndex(where: { $0.id == id }),
              let destinationIndex = items.firstIndex(where: { $0.id == destinationID }) else {
            return false
        }

        let item = items.remove(at: sourceIndex)
        items.insert(item, at: min(destinationIndex, items.count))
        return true
    }

    @discardableResult
    public mutating func move(ids: [UUID], to target: DockInsertionTarget) -> Bool {
        let requestedIDs = Set(ids)
        guard !requestedIDs.isEmpty else { return false }

        let movingItems = items.filter { requestedIDs.contains($0.id) }
        guard !movingItems.isEmpty else { return false }

        let boundary: Int
        switch target {
        case let .before(destinationID):
            guard let destinationIndex = items.firstIndex(where: { $0.id == destinationID }) else {
                return false
            }
            boundary = destinationIndex
        case let .after(destinationID):
            guard let destinationIndex = items.firstIndex(where: { $0.id == destinationID }) else {
                return false
            }
            boundary = destinationIndex + 1
        case .end:
            boundary = items.count
        }

        let removedBeforeBoundary = items[..<boundary].count(where: { requestedIDs.contains($0.id) })
        var reorderedItems = items.filter { !requestedIDs.contains($0.id) }
        let insertionIndex = min(max(0, boundary - removedBeforeBoundary), reorderedItems.count)
        reorderedItems.insert(contentsOf: movingItems, at: insertionIndex)

        guard reorderedItems != items else { return false }
        items = reorderedItems
        return true
    }

    public func itemsPreviewingMove(ids: [UUID], to target: DockInsertionTarget) -> [DockItem] {
        var preview = self
        _ = preview.move(ids: ids, to: target)
        return preview.items
    }

    @discardableResult
    public mutating func replace(id: UUID, with content: DockItemContent) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        items[index].content = content
        return true
    }

    public mutating func discardChanges() {
        items = savedItems
    }

    public mutating func markSaved(_ savedItems: [DockItem]) {
        self.savedItems = savedItems
        items = savedItems
    }

    public mutating func synchronize(with savedItems: [DockItem]) {
        let hadChanges = isDirty
        self.savedItems = savedItems
        if !hadChanges {
            items = savedItems
        }
    }
}
