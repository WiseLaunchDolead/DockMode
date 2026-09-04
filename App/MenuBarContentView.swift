import AppKit
import DockModeCore
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    let showManager: (Bool) -> Void
    let checkForUpdates: () -> Void
    let canCheckForUpdates: Bool

    var body: some View {
        Text("Docks")

        ForEach(model.profiles) { profile in
            Toggle(isOn: profileSelectionBinding(for: profile)) {
                Label {
                    Text(profile.name)
                } icon: {
                    Image(nsImage: ProfileMenuIconRenderer.image(for: profile.color))
                        .renderingMode(.original)
                }
            }
            .disabled(model.isSwitching)
        }

        if model.profiles.isEmpty {
            Button { showManager(false) } label: {
                Label("Finish DockMode Setup…", systemImage: "wand.and.stars")
            }
        }

        if !model.missingApplications.isEmpty {
            Divider()
            Label("Some profile applications are unavailable", systemImage: "exclamationmark.triangle")
        }

        Divider()
        Button { showManager(true) } label: {
            Label("New Profile…", systemImage: "plus.circle")
        }
            .disabled(model.profiles.isEmpty)
        Button { showManager(false) } label: {
            Label("Manage Profiles…", systemImage: "slider.horizontal.3")
        }

        Divider()
        Button(action: checkForUpdates) {
            Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
        }
            .disabled(!canCheckForUpdates)
        if model.launchAtLoginState == .requiresApproval {
            Label(
                "Launch at login requires approval in System Settings",
                systemImage: "exclamationmark.triangle"
            )
        }

        Divider()
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit DockMode", systemImage: "power")
        }
        .keyboardShortcut("q")
    }

    private func profileSelectionBinding(for profile: Profile) -> Binding<Bool> {
        Binding(
            get: { profile.id == model.document.activeProfileID },
            set: { shouldActivate in
                guard shouldActivate,
                      profile.id != model.document.activeProfileID else { return }

                do {
                    try model.switchProfile(to: profile.id)
                } catch {
                    model.presentError(error)
                }
            }
        )
    }
}
