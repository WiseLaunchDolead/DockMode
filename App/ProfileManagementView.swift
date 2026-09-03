import DockModeCore
import SwiftUI

struct ProfileManagementView: View {
    @ObservedObject var model: AppModel
    @State private var selection: UUID?
    @State private var isShowingFocusGuide = false

    var body: some View {
        Group {
            if model.needsOnboarding {
                ProfileEditorView(
                    profile: nil,
                    initialItems: model.onboardingItems,
                    availableApplications: model.applicationCatalog,
                    isFirstProfile: true,
                    canCancel: false,
                    onSave: createProfile,
                    onCancel: {}
                )
            } else {
                managementContent
            }
        }
        .sheet(isPresented: $model.isPresentingNewProfile) {
            ProfileEditorView(
                profile: nil,
                initialItems: model.activeProfile?.items ?? [],
                availableApplications: model.applicationCatalog,
                onSave: createProfile,
                onCancel: { model.isPresentingNewProfile = false }
            )
        }
        .alert("DockMode", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .sheet(isPresented: $isShowingFocusGuide) {
            FocusSetupGuideView()
        }
        .onAppear {
            if selection == nil { selection = model.document.activeProfileID }
            model.refreshLaunchAtLoginStatus()
        }
    }

    private var managementContent: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(model.profiles) { profile in
                    HStack(spacing: 9) {
                        Circle()
                            .fill(Color(profileColor: profile.color))
                            .frame(width: 10, height: 10)
                        Text(profile.name)
                        Spacer()
                        if profile.id == model.document.activeProfileID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(profile.id)
                }
            }
            .navigationTitle("Profiles")
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button {
                        model.isPresentingNewProfile = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New profile")
                    Spacer()
                }
                .padding(10)
                .background(.bar)
            }
            .frame(minWidth: 220)
        } detail: {
            if let profile = selectedProfile {
                VStack(spacing: 0) {
                    ProfileEditorView(
                        profile: profile,
                        initialItems: profile.items,
                        availableApplications: model.applicationCatalog,
                        canCancel: false,
                        onSave: { name, color, items in
                            do {
                                try model.updateProfile(id: profile.id, name: name, color: color, items: items)
                            } catch {
                                model.presentError(error)
                            }
                        },
                        onCancel: {}
                    )
                    .id(profile.updatedAt)

                    managementFooter(for: profile)
                }
            } else {
                ContentUnavailableView("Select a profile", systemImage: "rectangle.3.group")
            }
        }
        .frame(minWidth: 980, minHeight: 650)
    }

    private var selectedProfile: Profile? {
        let id = selection ?? model.document.activeProfileID
        return model.profiles.first(where: { $0.id == id })
    }

    @ViewBuilder
    private func managementFooter(for profile: Profile) -> some View {
        HStack(spacing: 16) {
            Button {
                isShowingFocusGuide = true
            } label: {
                Label("Focus Setup…", systemImage: "moon.stars")
            }

            Spacer()

            if model.launchAtLoginState == .requiresApproval {
                Label("Launch at login needs approval", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button("Export Logs…") {
                Task {
                    do {
                        _ = try await DiagnosticsExporter.export()
                    } catch {
                        model.presentError(error)
                    }
                }
            }

            Button("Delete Profile", role: .destructive) {
                do {
                    try model.deleteProfile(id: profile.id)
                    selection = model.document.activeProfileID
                } catch {
                    model.presentError(error)
                }
            }
            .disabled(model.profiles.count <= 1 || model.document.activeProfileID == profile.id)
        }
        .padding(12)
        .background(.bar)
    }

    private func createProfile(name: String, color: ProfileColor, items: [DockItem]) {
        do {
            try model.createProfile(name: name, color: color, items: items)
            selection = model.document.activeProfileID
            model.isPresentingNewProfile = false
        } catch {
            model.presentError(error)
        }
    }
}

private struct FocusSetupGuideView: View {
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
