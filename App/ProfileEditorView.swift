import AppKit
import DockModeCore
import SwiftUI
import UniformTypeIdentifiers

struct ProfileEditorView: View {
    let profileID: UUID?
    let availableApplications: [ApplicationReference]
    let isFirstProfile: Bool
    let canCancel: Bool
    let onSave: (String, ProfileColor, [DockItem]) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var color: ProfileColor
    @State private var items: [DockItem]
    @State private var searchText = ""
    @State private var draggedItemID: UUID?

    init(
        profile: Profile?,
        initialItems: [DockItem],
        availableApplications: [ApplicationReference],
        isFirstProfile: Bool = false,
        canCancel: Bool = true,
        onSave: @escaping (String, ProfileColor, [DockItem]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        profileID = profile?.id
        self.availableApplications = availableApplications
        self.isFirstProfile = isFirstProfile
        self.canCancel = canCancel
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: profile?.name ?? "")
        _color = State(initialValue: profile?.color ?? .blue)
        _items = State(initialValue: profile?.items ?? initialItems)
    }

    private var filteredApplications: [ApplicationReference] {
        guard !searchText.isEmpty else { return availableApplications }
        return availableApplications.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var selectedApplicationKeys: Set<String> {
        Set(items.compactMap { item in
            guard case let .application(reference) = item.content else { return nil }
            return reference.stableKey
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                applicationPicker
                    .frame(minWidth: 280, idealWidth: 330)
                dockLayout
                    .frame(minWidth: 360, idealWidth: 440)
            }
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 560)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isFirstProfile ? "Create your first profile" : profileID == nil ? "New profile" : "Edit profile")
                .font(.title2.bold())

            HStack(spacing: 12) {
                TextField("Profile name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)

                ForEach(Array(ProfileColor.palette.enumerated()), id: \.offset) { _, paletteColor in
                    Button {
                        color = paletteColor
                    } label: {
                        Circle()
                            .fill(Color(profileColor: paletteColor))
                            .frame(width: 18, height: 18)
                            .overlay {
                                if color == paletteColor {
                                    Circle().stroke(.primary, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose profile color")
                }

                ColorPicker("Custom color", selection: Binding(
                    get: { Color(profileColor: color) },
                    set: { color = ProfileColor(swiftUIColor: $0) }
                ), supportsOpacity: false)
                .labelsHidden()
            }
        }
        .padding(20)
    }

    private var applicationPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Applications")
                .font(.headline)
            TextField("Search applications", text: $searchText)
                .textFieldStyle(.roundedBorder)

            List(filteredApplications, id: \.stableKey) { application in
                let isSelected = selectedApplicationKeys.contains(application.stableKey)
                Button {
                    toggle(application)
                } label: {
                    HStack(spacing: 9) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: application.lastKnownPath))
                            .resizable()
                            .frame(width: 24, height: 24)
                        Text(application.displayName)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if filteredApplications.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .padding(16)
    }

    private var dockLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Profile Dock")
                    .font(.headline)
                Spacer()
                Menu("Add spacer", systemImage: "rectangle.split.3x1") {
                    Button("Compact") { items.append(.spacer(.compact)) }
                    Button("Standard") { items.append(.spacer(.regular)) }
                    Button("Flexible") { items.append(.spacer(.flexible)) }
                }
            }

            List {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    DockItemRow(item: item) {
                        items.removeAll(where: { $0.id == item.id })
                    } moveUp: {
                        guard index > 0 else { return }
                        items.swapAt(index, index - 1)
                    } moveDown: {
                        guard index + 1 < items.count else { return }
                        items.swapAt(index, index + 1)
                    }
                    .onDrag {
                        draggedItemID = item.id
                        return NSItemProvider(object: item.id.uuidString as NSString)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: DockItemDropDelegate(
                            destinationID: item.id,
                            items: $items,
                            draggedItemID: $draggedItemID
                        )
                    )
                }
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Empty Dock",
                        systemImage: "dock.rectangle",
                        description: Text("Select applications or add a spacer.")
                    )
                }
            }

            Text("Drag items to change their order. Applications already open are never closed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            if isFirstProfile {
                Text("Folders, recent apps and other Dock settings stay untouched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if canCancel {
                Button("Cancel", action: onCancel)
            }
            Button(profileID == nil ? "Create Profile" : "Save Changes") {
                onSave(name, color, items)
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
    }

    private func toggle(_ application: ApplicationReference) {
        if selectedApplicationKeys.contains(application.stableKey) {
            items.removeAll { item in
                guard case let .application(reference) = item.content else { return false }
                return reference.stableKey == application.stableKey
            }
        } else {
            items.append(.application(application))
        }
    }
}

private struct DockItemRow: View {
    let item: DockItem
    let remove: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            switch item.content {
            case let .application(application):
                Image(nsImage: NSWorkspace.shared.icon(forFile: application.lastKnownPath))
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(application.displayName)
                    if !FileManager.default.fileExists(atPath: application.lastKnownPath) {
                        Text("Application unavailable")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            case let .spacer(kind):
                Image(systemName: "rectangle.split.3x1")
                    .frame(width: 28, height: 28)
                Text(spacerName(kind))
            }
            Spacer()
            Button(action: remove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Remove item")
        }
        .padding(.vertical, 3)
        .accessibilityAction(named: Text("Move up"), moveUp)
        .accessibilityAction(named: Text("Move down"), moveDown)
    }

    private func spacerName(_ kind: SpacerKind) -> LocalizedStringKey {
        switch kind {
        case .compact: "Compact spacer"
        case .regular: "Standard spacer"
        case .flexible: "Flexible spacer"
        }
    }
}

private struct DockItemDropDelegate: DropDelegate {
    let destinationID: UUID
    @Binding var items: [DockItem]
    @Binding var draggedItemID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedItemID,
              draggedItemID != destinationID,
              let from = items.firstIndex(where: { $0.id == draggedItemID }),
              let to = items.firstIndex(where: { $0.id == destinationID }) else {
            return
        }
        withAnimation {
            items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItemID = nil
        return true
    }
}
