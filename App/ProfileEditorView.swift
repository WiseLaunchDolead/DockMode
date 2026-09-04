import AppKit
import DockModeCore
import SwiftUI
import UniformTypeIdentifiers

extension ApplicationReference {
    var resolvedInstalledURL: URL? {
        let knownURL = URL(fileURLWithPath: lastKnownPath)
        if FileManager.default.fileExists(atPath: knownURL.path) {
            return knownURL
        }
        guard let bundleIdentifier else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }
}

struct DockPreviewView: View {
    @Binding var draft: DockLayoutDraft
    @Binding var draggedItemID: UUID?
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let iconSize = preferredIconSize(for: proxy.size.width)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: max(8, iconSize * 0.16)) {
                    ForEach(Array(draft.items.enumerated()), id: \.element.id) { index, item in
                        DockPreviewItemView(
                            item: item,
                            index: index,
                            totalCount: draft.items.count,
                            iconSize: iconSize,
                            draft: $draft,
                            draggedItemID: $draggedItemID
                        )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(minWidth: min(proxy.size.width - 32, 260))
                .dockModeGlassSurface(tint: tint.opacity(0.18), cornerRadius: 24)
                .padding(.horizontal, 16)
                .frame(minWidth: proxy.size.width)
            }
            .overlay {
                if draft.items.isEmpty {
                    ContentUnavailableView(
                        "Empty Dock",
                        systemImage: "dock.rectangle",
                        description: Text("Add applications or a spacer from Edit Dock.")
                    )
                }
            }
        }
        .frame(height: 126)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dock Preview")
    }

    private func preferredIconSize(for availableWidth: CGFloat) -> CGFloat {
        guard !draft.items.isEmpty else { return 54 }
        let spacerWeight = draft.items.reduce(CGFloat.zero) { partial, item in
            switch item.content {
            case .application: partial + 1
            case .spacer(.compact): partial + 0.28
            case .spacer(.regular): partial + 0.55
            case .spacer(.flexible): partial + 0.9
            }
        }
        let availableForItems = max(0, availableWidth - 110)
        return min(58, max(38, availableForItems / max(1, spacerWeight)))
    }
}

private struct DockPreviewItemView: View {
    let item: DockItem
    let index: Int
    let totalCount: Int
    let iconSize: CGFloat
    @Binding var draft: DockLayoutDraft
    @Binding var draggedItemID: UUID?

    var body: some View {
        itemContent
            .contentShape(Rectangle())
            .onDrag {
                draggedItemID = item.id
                return NSItemProvider(object: item.id.uuidString as NSString)
            }
            .onDrop(
                of: [UTType.text],
                delegate: DockPreviewDropDelegate(
                    destinationID: item.id,
                    draft: $draft,
                    draggedItemID: $draggedItemID
                )
            )
            .contextMenu {
                Button("Move Left", systemImage: "arrow.left") {
                    withAnimation(.snappy) {
                        _ = draft.move(id: item.id, direction: .left)
                    }
                }
                .disabled(index == 0)

                Button("Move Right", systemImage: "arrow.right") {
                    withAnimation(.snappy) {
                        _ = draft.move(id: item.id, direction: .right)
                    }
                }
                .disabled(index + 1 >= totalCount)

                Divider()

                Button(role: .destructive) {
                    withAnimation(.snappy) {
                        _ = draft.remove(id: item.id)
                    }
                } label: {
                    Label(removalLabel, systemImage: "trash")
                }
            }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAction(named: Text("Move Left")) {
                _ = draft.move(id: item.id, direction: .left)
            }
            .accessibilityAction(named: Text("Move Right")) {
                _ = draft.move(id: item.id, direction: .right)
            }
            .accessibilityAction(named: Text(removalLabel)) {
                _ = draft.remove(id: item.id)
            }
    }

    @ViewBuilder
    private var itemContent: some View {
        switch item.content {
        case let .application(application):
            if let applicationURL = application.resolvedInstalledURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: applicationURL.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
                    .help(application.displayName)
            } else {
                Image(systemName: "questionmark.app.dashed")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.orange)
                    .frame(width: iconSize, height: iconSize)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    .help("Application unavailable")
            }

        case let .spacer(kind):
            SpacerPreview(kind: kind, iconSize: iconSize)
        }
    }

    private var removalLabel: LocalizedStringKey {
        switch item.content {
        case .application: "Remove Application"
        case .spacer: "Remove Spacer"
        }
    }

    private var accessibilityLabel: Text {
        switch item.content {
        case let .application(application):
            Text("Application: \(application.displayName)")
        case let .spacer(kind):
            Text(spacerLabel(kind))
        }
    }

    private func spacerLabel(_ kind: SpacerKind) -> LocalizedStringKey {
        switch kind {
        case .compact: "Small Spacer"
        case .regular: "Regular Spacer"
        case .flexible: "Flexible Spacer"
        }
    }
}

private struct SpacerPreview: View {
    let kind: SpacerKind
    let iconSize: CGFloat

    var body: some View {
        Group {
            if kind == .flexible {
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: max(11, iconSize * 0.24), weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(.white.opacity(0.42))
                    .overlay {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(.white.opacity(0.55), lineWidth: 0.7)
                    }
                    .frame(width: kind == .compact ? 4 : 7, height: iconSize * 0.76)
            }
        }
        .frame(width: spacerWidth, height: iconSize)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var spacerWidth: CGFloat {
        switch kind {
        case .compact: max(12, iconSize * 0.28)
        case .regular: max(24, iconSize * 0.55)
        case .flexible: max(44, iconSize * 0.9)
        }
    }
}

private struct DockPreviewDropDelegate: DropDelegate {
    let destinationID: UUID
    @Binding var draft: DockLayoutDraft
    @Binding var draggedItemID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedItemID, draggedItemID != destinationID else { return }
        withAnimation(.snappy) {
            _ = draft.reorder(id: draggedItemID, toPositionOf: destinationID)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItemID = nil
        return true
    }
}

struct ApplicationPickerSheet: View {
    let applications: [ApplicationReference]
    let excludedKeys: Set<String>
    let onAdd: ([ApplicationReference]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedKeys: [String] = []

    private var filteredApplications: [ApplicationReference] {
        guard !searchText.isEmpty else { return applications }
        return applications.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var selectedApplications: [ApplicationReference] {
        selectedKeys.compactMap { key in applications.first(where: { $0.stableKey == key }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add Applications")
                    .font(.title2.bold())
                TextField("Search applications", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(20)

            Divider()

            List(filteredApplications, id: \.stableKey) { application in
                let isExcluded = excludedKeys.contains(application.stableKey)
                let isSelected = selectedKeys.contains(application.stableKey)
                Button {
                    toggle(application)
                } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: application.lastKnownPath))
                            .resizable()
                            .frame(width: 30, height: 30)
                        Text(application.displayName)
                            .lineLimit(1)
                        Spacer()
                        if isExcluded {
                            Text("Already Added")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isExcluded)
                .accessibilityLabel(application.displayName)
                .accessibilityValue(isExcluded ? Text("Already Added") : Text(isSelected ? "Selected" : "Not Selected"))
            }
            .overlay {
                if filteredApplications.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add Applications") {
                    onAdd(selectedApplications)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedKeys.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 560, height: 540)
    }

    private func toggle(_ application: ApplicationReference) {
        if let index = selectedKeys.firstIndex(of: application.stableKey) {
            selectedKeys.remove(at: index)
        } else {
            selectedKeys.append(application.stableKey)
        }
    }
}

struct ProfileFormSheet: View {
    let title: LocalizedStringKey
    let initialName: String
    let initialColor: ProfileColor
    let canCancel: Bool
    let onSave: (String, ProfileColor) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var color: ProfileColor
    @State private var errorMessage: String?

    init(
        title: LocalizedStringKey,
        initialName: String = "",
        initialColor: ProfileColor = .blue,
        canCancel: Bool = true,
        onSave: @escaping (String, ProfileColor) throws -> Void
    ) {
        self.title = title
        self.initialName = initialName
        self.initialColor = initialColor
        self.canCancel = canCancel
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _color = State(initialValue: initialColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.title2.bold())
            TextField("Profile name", text: $name)
                .textFieldStyle(.roundedBorder)
            ProfileColorControls(color: $color)
            HStack {
                Spacer()
                if canCancel { Button("Cancel") { dismiss() } }
                Button(initialName.isEmpty ? "Create Profile" : "Save Changes") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
        .alert("DockMode", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() {
        do {
            try onSave(name, color)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct RenameProfileSheet: View {
    let onSave: (String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var errorMessage: String?

    init(currentName: String, onSave: @escaping (String) throws -> Void) {
        self.onSave = onSave
        _name = State(initialValue: currentName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Rename Profile").font(.title2.bold())
            TextField("Profile name", text: $name).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Rename") {
                    do {
                        try onSave(name)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .alert("DockMode", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

struct CustomColorSheet: View {
    let onSave: (ProfileColor) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var color: ProfileColor
    @State private var errorMessage: String?

    init(initialColor: ProfileColor, onSave: @escaping (ProfileColor) throws -> Void) {
        self.onSave = onSave
        _color = State(initialValue: initialColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Custom Color").font(.title2.bold())
            ColorPicker(
                "Profile Color",
                selection: Binding(
                    get: { Color(profileColor: color) },
                    set: { color = ProfileColor(swiftUIColor: $0) }
                ),
                supportsOpacity: false
            )
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save Changes") {
                    do {
                        try onSave(color)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 380)
        .alert("DockMode", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

struct ProfileColorControls: View {
    @Binding var color: ProfileColor

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(ProfileColor.palette.enumerated()), id: \.offset) { _, paletteColor in
                Button { color = paletteColor } label: {
                    Circle()
                        .fill(Color(profileColor: paletteColor))
                        .frame(width: 22, height: 22)
                        .overlay {
                            if color == paletteColor { Circle().stroke(.primary, lineWidth: 2) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose Profile Color")
            }
            ColorPicker(
                "Custom Color",
                selection: Binding(
                    get: { Color(profileColor: color) },
                    set: { color = ProfileColor(swiftUIColor: $0) }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
        }
    }
}

struct DockModeWindowBackground: View {
    let tint: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                VisualEffectBackdrop()
                LinearGradient(
                    colors: [tint.opacity(0.30), Color.white.opacity(0.08), tint.opacity(0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }
}

private struct VisualEffectBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct AdaptiveGlassSurface: ViewModifier {
    let tint: Color
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(
                    Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.primary.opacity(colorSchemeContrast == .increased ? 0.42 : 0.16), lineWidth: 1)
                }
        } else if #available(macOS 26.0, *) {
            content.glassEffect(
                .regular.tint(tint),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            .primary.opacity(colorSchemeContrast == .increased ? 0.38 : 0.12),
                            lineWidth: 1
                        )
                }
        }
    }
}

enum DockModeButtonEmphasis {
    case standard
    case prominent
}

private struct AdaptiveGlassButton: ViewModifier {
    let emphasis: DockModeButtonEmphasis
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            switch emphasis {
            case .standard: content.buttonStyle(.glass)
            case .prominent: content.buttonStyle(.glassProminent).tint(tint)
            }
        } else {
            switch emphasis {
            case .standard: content.buttonStyle(.bordered)
            case .prominent: content.buttonStyle(.borderedProminent).tint(tint)
            }
        }
    }
}

extension View {
    func dockModeGlassSurface(tint: Color = .clear, cornerRadius: CGFloat) -> some View {
        modifier(AdaptiveGlassSurface(tint: tint, cornerRadius: cornerRadius))
    }

    func dockModeGlassButton(
        _ emphasis: DockModeButtonEmphasis = .standard,
        tint: Color = .accentColor
    ) -> some View {
        modifier(AdaptiveGlassButton(emphasis: emphasis, tint: tint))
    }
}
