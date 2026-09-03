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
                HStack {
                    Circle()
                        .fill(Color(profileColor: profile.color))
                        .frame(width: 8, height: 8)
                    Text(profile.name)
                    if profile.id == model.document.activeProfileID {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .disabled(model.isSwitching)
        }

        if model.profiles.isEmpty {
            Button("Finish DockMode Setup…") { showManager(false) }
        }

        if !model.missingApplications.isEmpty {
            Divider()
            Text("Some profile applications are unavailable")
        }

        Divider()
        Button("New Profile…") { showManager(true) }
            .disabled(model.profiles.isEmpty)
        Button("Manage Profiles…") { showManager(false) }

        Divider()
        Button("Check for Updates…", action: checkForUpdates)
            .disabled(!canCheckForUpdates)
        if model.launchAtLoginState == .requiresApproval {
            Text("Launch at login requires approval in System Settings")
        }

        Divider()
        Button("Quit DockMode") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
