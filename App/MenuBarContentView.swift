import AppKit
import DockModeCore
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    let showManager: (Bool) -> Void
    let checkForUpdates: () -> Void
    let canCheckForUpdates: Bool

    var body: some View {
        ForEach(model.profiles) { profile in
            Button {
                do {
                    try model.switchProfile(to: profile.id)
                } catch {
                    model.presentError(error)
                }
            } label: {
                Label {
                    Text(profile.name)
                } icon: {
                    Image(systemName: profile.id == model.document.activeProfileID
                        ? "checkmark.circle.fill"
                        : "circle.fill")
                        .foregroundStyle(Color(profileColor: profile.color))
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
}
