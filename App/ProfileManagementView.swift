import DockModeCore
import SwiftUI

struct ProfileManagementView: View {
    @ObservedObject var model: AppModel

    @State private var selectedProfileID: UUID?
    @State private var previousActiveProfileID: UUID?
    @State private var draft = DockLayoutDraft(savedItems: [])
    @State private var draftProfileID: UUID?
    @State private var draggedItemID: UUID?
    @State private var pendingAction: PendingEditorAction?
    @State private var isShowingUnsavedAlert = false
    @State private var profileFormMode: ProfileFormMode?
    @State private var isShowingApplicationPicker = false
    @State private var isShowingRename = false
    @State private var isShowingCustomColor = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingFocusGuide = false

    var body: some View {
        ZStack {
            DockModeWindowBackground(tint: profileTint)

            if model.needsOnboarding {
                onboardingContent
            } else if let profile = selectedProfile {
                editorContent(profile: profile)
            } else {
                ContentUnavailableView("Select a profile", systemImage: "rectangle.3.group")
            }
        }
        .frame(minWidth: 720, minHeight: 360)
        .sheet(item: $profileFormMode) { mode in
            ProfileFormSheet(
                title: mode == .first ? "Create your first profile" : "New profile",
                initialColor: model.activeProfile?.color ?? .blue,
                canCancel: mode != .first
            ) { name, color in
                let initialItems = mode == .first
                    ? model.onboardingItems
                    : (model.activeProfile?.items ?? [])
                try model.createProfile(name: name, color: color, items: initialItems)
                if let activeID = model.document.activeProfileID {
                    loadProfile(activeID)
                }
                model.isPresentingNewProfile = false
            }
            .interactiveDismissDisabled(mode == .first)
        }
        .sheet(isPresented: $isShowingApplicationPicker) {
            ApplicationPickerSheet(
                applications: model.applicationCatalog,
                excludedKeys: selectedApplicationKeys
            ) { applications in
                withAnimation(.snappy) {
                    for application in applications {
                        _ = draft.addApplication(application)
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingRename) {
            if let profile = selectedProfile {
                RenameProfileSheet(currentName: profile.name) { name in
                    try model.renameProfile(id: profile.id, name: name)
                }
            }
        }
        .sheet(isPresented: $isShowingCustomColor) {
            if let profile = selectedProfile {
                CustomColorSheet(initialColor: profile.color) { color in
                    try model.recolorProfile(id: profile.id, color: color)
                }
            }
        }
        .sheet(isPresented: $isShowingFocusGuide) {
            FocusSetupGuideView()
        }
        .alert("Unsaved Changes", isPresented: $isShowingUnsavedAlert) {
            Button("Save Changes") { resolveUnsavedChanges(.save) }
            Button("Discard Changes", role: .destructive) { resolveUnsavedChanges(.discard) }
            Button("Cancel", role: .cancel) { resolveUnsavedChanges(.cancel) }
        } message: {
            Text("Save your Dock changes before continuing?")
        }
        .alert("Delete Profile?", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete Profile", role: .destructive) { deleteSelectedProfile() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This profile and its saved Dock layout will be permanently deleted.")
        }
        .alert("DockMode", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .onAppear {
            previousActiveProfileID = model.document.activeProfileID
            if model.needsOnboarding {
                profileFormMode = .first
            } else if draftProfileID == nil, let activeID = model.document.activeProfileID {
                loadProfile(activeID)
            }
            if model.isPresentingNewProfile, !model.needsOnboarding {
                model.isPresentingNewProfile = false
                requestNewProfile()
            }
            model.refreshLaunchAtLoginStatus()
        }
        .onChange(of: model.profiles) { _, _ in
            synchronizeSelectedProfile()
        }
        .onChange(of: model.document.activeProfileID) { _, newActiveID in
            let shouldFollowActive = selectedProfileID == previousActiveProfileID && !draft.isDirty
            previousActiveProfileID = newActiveID
            if shouldFollowActive, let newActiveID {
                loadProfile(newActiveID)
            }
        }
        .onChange(of: model.isPresentingNewProfile) { _, shouldPresent in
            guard shouldPresent, !model.needsOnboarding else { return }
            requestNewProfile()
            model.isPresentingNewProfile = false
        }
    }

    private var onboardingContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "dock.rectangle")
                .font(.system(size: 48, weight: .light))
            Text("Create your first profile")
                .font(.title2.bold())
            Text("Your current pinned applications will be used as the starting layout.")
                .foregroundStyle(.secondary)
            Button("Create Profile") { profileFormMode = .first }
                .dockModeGlassButton(.prominent, tint: .blue)
        }
        .padding(36)
        .dockModeGlassSurface(tint: .blue.opacity(0.12), cornerRadius: 28)
    }

    private func editorContent(profile: Profile) -> some View {
        VStack(spacing: 20) {
            header(profile: profile)

            DockPreviewView(
                draft: $draft,
                draggedItemID: $draggedItemID,
                tint: Color(profileColor: profile.color)
            )
            .padding(.vertical, 22)
            .dockModeGlassSurface(
                tint: Color(profileColor: profile.color).opacity(0.10),
                cornerRadius: 30
            )

            footer(profile: profile)
        }
        .padding(.top, 18)
        .padding(.horizontal, 26)
        .padding(.bottom, 22)
    }

    private func header(profile: Profile) -> some View {
        HStack(alignment: .top, spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(.white.opacity(0.58))
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(profileColor: profile.color))
                        .padding(9)
                }
                .frame(width: 48, height: 48)
                .shadow(color: .black.opacity(0.10), radius: 5, y: 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.name)
                        .font(.title2.bold())
                        .lineLimit(1)
                    statusLine(profile: profile)
                }
            }

            Spacer(minLength: 18)

            VStack(alignment: .trailing, spacing: 12) {
                profileMenu(profile: profile)
                actionButtons(profile: profile)
            }
        }
    }

    private func statusLine(profile: Profile) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor(profile: profile))
                .frame(width: 8, height: 8)
            Text(statusLabel(profile: profile))
            Text("•")
            Text(itemCountText)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func actionButtons(profile: Profile) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                actionButtonRow(profile: profile)
            }
        } else {
            actionButtonRow(profile: profile)
        }
    }

    private func actionButtonRow(profile: Profile) -> some View {
        HStack(spacing: 10) {
            if draft.isDirty {
                Button("Save Changes") { _ = saveDraft() }
                    .dockModeGlassButton(.prominent, tint: Color(profileColor: profile.color))
            }

            if profile.id != model.document.activeProfileID {
                Button("Use This Dock") { useSelectedDock() }
                    .dockModeGlassButton(.prominent, tint: Color(profileColor: profile.color))
                    .disabled(draft.isDirty || model.isSwitching)
            }

            editDockMenu
                .dockModeGlassButton()
                .disabled(model.isSwitching)
        }
    }

    private var editDockMenu: some View {
        Menu("Edit Dock", systemImage: "slider.horizontal.3") {
            Button("Add Applications…", systemImage: "app.badge.plus") {
                isShowingApplicationPicker = true
            }
            Menu("Add Spacer", systemImage: "rectangle.split.3x1") {
                Button("Small") {
                    withAnimation(.snappy) { draft.addSpacer(.compact) }
                }
                Button("Regular") {
                    withAnimation(.snappy) { draft.addSpacer(.regular) }
                }
            }
        }
    }

    private func profileMenu(profile: Profile) -> some View {
        Menu {
            ForEach(model.profiles) { candidate in
                Button {
                    requestProfileSelection(candidate.id)
                } label: {
                    HStack {
                        Text(candidate.name)
                        if candidate.id == selectedProfileID {
                            Image(systemName: "checkmark")
                        }
                        if candidate.id == model.document.activeProfileID {
                            Text("Current")
                        }
                    }
                }
            }

            Divider()

            Button("New Profile…", systemImage: "plus") { requestNewProfile() }
            Button("Rename…", systemImage: "pencil") { isShowingRename = true }

            Menu("Change Color", systemImage: "paintpalette") {
                ForEach(Array(ProfileColor.palette.enumerated()), id: \.offset) { index, color in
                    Button(paletteColorName(index)) {
                        do {
                            try model.recolorProfile(id: profile.id, color: color)
                        } catch {
                            model.presentError(error)
                        }
                    }
                }
                Divider()
                Button("Custom Color…") { isShowingCustomColor = true }
            }

            Button("Delete Profile…", systemImage: "trash", role: .destructive) {
                isShowingDeleteConfirmation = true
            }
            .disabled(model.profiles.count <= 1 || profile.id == model.document.activeProfileID)

            Divider()

            Button("Focus Setup…", systemImage: "moon.stars") { isShowingFocusGuide = true }
            Button("Export Logs…", systemImage: "doc.text") { exportLogs() }
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(profileColor: profile.color))
                    .frame(width: 18, height: 18)
                Text(profile.name)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .dockModeGlassButton()
    }

    private func footer(profile: Profile) -> some View {
        HStack(spacing: 12) {
            if !missingApplications.isEmpty {
                Label("Some profile applications are unavailable", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Text("Drag items to reorder. Right-click an item for more actions.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.launchAtLoginState == .requiresApproval {
                Label("Launch at login needs approval", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
    }

    private var selectedProfile: Profile? {
        guard let selectedProfileID else { return nil }
        return model.profiles.first(where: { $0.id == selectedProfileID })
    }

    private var profileTint: Color {
        selectedProfile.map { Color(profileColor: $0.color) } ?? .blue
    }

    private var selectedApplicationKeys: Set<String> {
        Set(draft.items.compactMap { item in
            guard case let .application(application) = item.content else { return nil }
            return application.stableKey
        })
    }

    private var missingApplications: [ApplicationReference] {
        draft.items.compactMap { item in
            guard case let .application(application) = item.content,
                  application.resolvedInstalledURL == nil else {
                return nil
            }
            return application
        }
    }

    private var itemCountText: String {
        let count = draft.items.count
        if count == 1 {
            return NSLocalizedString("1 item", comment: "Singular Dock item count")
        }
        return String.localizedStringWithFormat(
            NSLocalizedString("%d items", comment: "Plural Dock item count"),
            count
        )
    }

    private func statusLabel(profile: Profile) -> LocalizedStringKey {
        if draft.isDirty { return "Unsaved" }
        return profile.id == model.document.activeProfileID ? "Current" : "Not Active"
    }

    private func statusColor(profile: Profile) -> Color {
        if draft.isDirty { return .orange }
        return profile.id == model.document.activeProfileID
            ? Color(profileColor: profile.color)
            : .secondary
    }

    private func requestProfileSelection(_ profileID: UUID) {
        guard profileID != selectedProfileID else { return }
        if draft.isDirty {
            pendingAction = .select(profileID)
            isShowingUnsavedAlert = true
        } else {
            loadProfile(profileID)
        }
    }

    private func requestNewProfile() {
        if draft.isDirty {
            pendingAction = .createProfile
            isShowingUnsavedAlert = true
        } else {
            profileFormMode = .new
        }
    }

    @discardableResult
    private func saveDraft() -> Bool {
        guard let profileID = draftProfileID else { return false }
        do {
            try model.saveDockLayout(profileID: profileID, items: draft.items)
            if let saved = model.profiles.first(where: { $0.id == profileID }) {
                draft.markSaved(saved.items)
            }
            return true
        } catch {
            model.presentError(error)
            return false
        }
    }

    private func resolveUnsavedChanges(_ choice: UnsavedDraftChoice) {
        switch UnsavedDraftPolicy.effect(for: choice) {
        case .saveAndContinue:
            guard saveDraft() else { return }
            performPendingAction()
        case .discardAndContinue:
            draft.discardChanges()
            performPendingAction()
        case .stay:
            pendingAction = nil
        }
    }

    private func performPendingAction() {
        let action = pendingAction
        pendingAction = nil
        switch action {
        case let .select(profileID): loadProfile(profileID)
        case .createProfile: profileFormMode = .new
        case nil: break
        }
    }

    private func loadProfile(_ profileID: UUID) {
        guard let profile = model.profiles.first(where: { $0.id == profileID }) else { return }
        selectedProfileID = profileID
        draftProfileID = profileID
        draft = DockLayoutDraft(savedItems: profile.items)
        draggedItemID = nil
    }

    private func synchronizeSelectedProfile() {
        guard let selectedProfileID,
              let profile = model.profiles.first(where: { $0.id == selectedProfileID }) else {
            if let activeID = model.document.activeProfileID {
                loadProfile(activeID)
            }
            return
        }

        if draftProfileID == selectedProfileID {
            draft.synchronize(with: profile.items)
        } else {
            loadProfile(selectedProfileID)
        }
    }

    private func useSelectedDock() {
        guard !draft.isDirty, let profileID = selectedProfileID else { return }
        do {
            try model.switchProfile(to: profileID)
            if let profile = model.profiles.first(where: { $0.id == profileID }) {
                draft.markSaved(profile.items)
            }
        } catch {
            model.presentError(error)
        }
    }

    private func deleteSelectedProfile() {
        guard let profileID = selectedProfileID else { return }
        do {
            try model.deleteProfile(id: profileID)
            if let activeID = model.document.activeProfileID {
                loadProfile(activeID)
            }
        } catch {
            model.presentError(error)
        }
    }

    private func exportLogs() {
        Task {
            do {
                _ = try await DiagnosticsExporter.export()
            } catch {
                model.presentError(error)
            }
        }
    }

    private func paletteColorName(_ index: Int) -> LocalizedStringKey {
        switch index {
        case 0: "Blue"
        case 1: "Purple"
        case 2: "Pink"
        case 3: "Red"
        case 4: "Orange"
        case 5: "Yellow"
        case 6: "Green"
        default: "Teal"
        }
    }
}

private enum PendingEditorAction {
    case select(UUID)
    case createProfile
}

private enum ProfileFormMode: String, Identifiable {
    case first
    case new

    var id: String { rawValue }
}

struct FocusSetupGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Switch profiles with Focus", systemImage: "moon.stars.fill")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 12) {
                guideStep(1, "Open System Settings › Focus.")
                guideStep(2, "Choose a Focus, add a filter, then select DockMode.")
                guideStep(3, "Choose the DockMode profile to activate.")
            }

            Text("DockMode restores the previous profile when the Focus ends. Automation works while DockMode is running; a pending request is applied at the next launch.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 540)
    }

    private func guideStep(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(.quaternary, in: Circle())
            Text(text)
        }
    }
}
