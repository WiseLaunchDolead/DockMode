# DockMode

DockMode is a native macOS menu-bar app that keeps a separate set of pinned Dock applications and spacers for every context in your day.

It changes the real macOS Dock. It never launches, quits, hides, or blocks applications. Folders, recent applications, minimized windows, and every other Dock preference remain untouched.

## Features

- Unlimited profiles with a name and color.
- One-click profile switching from the menu bar, with each profile's color shown in the native menu.
- Compact Liquid Glass editor with a responsive live Dock preview on macOS 26 and a Material fallback on macOS 14/15.
- Searchable multi-application picker, Command-click multi-selection, grouped drag-to-reorder editing, and explicit save/apply actions.
- Compact and standard native Dock spacers; existing flexible spacers remain editable for compatibility.
- Automatic capture of manual Dock additions, removals, and reordering.
- Native Focus filter that can activate a profile with a macOS Focus.
- Local-only storage, no account, cloud synchronization, analytics, or network service.
- Manual one-day `OSLog` export with home-directory paths redacted.
- French and English interface.
- Manual, redacted export of DockMode-only unified logs.
- Direct distribution from GitHub Releases. The supported public build does not require an Apple Developer account; updates are downloaded and installed manually.

## How profile switching behaves

DockMode reads and writes only the `persistent-apps` key in the current user's `com.apple.dock` preferences. A switch follows a guarded transaction:

1. Save the latest manual changes in the active profile.
2. Keep the raw current Dock as a rollback snapshot.
3. Resolve every target application by path, then bundle identifier.
4. Write and verify the target pinned applications and spacers.
5. Restart the Dock briefly.
6. Restore the snapshot if verification fails.

An unavailable application remains in its profile and is skipped until it is installed again. An application that is merely running is not added to a profile; it must be pinned with **Keep in Dock**.

> macOS does not expose a public API for replacing pinned Dock items. DockMode uses the established `CFPreferences` representation used by the native Dock. Compatibility must be checked for every major macOS release.

## Focus setup

DockMode ships an App Intents extension implementing a native Focus filter:

1. Create the DockMode profiles you need.
2. Open **System Settings → Focus**.
3. Choose a Focus, add a filter, then select **DockMode**.
4. Choose the profile that should be applied.

When the Focus ends, DockMode restores the profile that was active before it began. A manual profile selection wins until the next Focus activation or deactivation event. DockMode must be running for the Dock to change; launch at login is enabled after onboarding.

## Development

### Requirements

- macOS 14 or later.
- Swift 6.1 or later for the core module.
- Current full Xcode for the app and extension.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen).

The repository includes a Swift package for the testable core, plus an XcodeGen specification for the complete app:

```sh
swift run DockModeCoreChecks
brew install xcodegen
scripts/generate-project.sh
open DockMode.xcodeproj
```

The generated Xcode project is committed so the app can also be opened immediately. Regenerate it after changing `project.yml`.

The local core checks use an in-memory Dock preference store and never read or modify your actual Dock. Xcode unit tests exercise the same codecs, persistence, missing-app behavior, and rollback path.

### Local installation (unsigned development build)

To create a local app and DMG after installing Xcode:

```sh
xcodebuild build -project DockMode.xcodeproj -scheme DockMode -configuration Release \
  -destination 'generic/platform=macOS' ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/DerivedData
mkdir -p build/Release
ditto "build/DerivedData/Build/Products/Release/DockMode.app" build/Release/DockMode.app
scripts/create-dmg.sh build/Release/DockMode.app build/DockMode-local.dmg
```

Open `build/DockMode-local.dmg`, drag DockMode to **Applications**, then use **Open** from the Finder context menu if macOS warns that the development build is not signed. This is also the distribution path used when no Apple Developer account is available. On the first launch, macOS may require the user to approve the app in Finder or **System Settings → Privacy & Security**.

### Project structure

- `Sources/DockModeCore`: models, profile storage, app catalog, Focus request storage, and transactional Dock repository.
- `App`: menu-bar application, onboarding, profile editor, monitoring, launch-at-login, and Sparkle controller.
- `FocusExtension`: native `SetFocusFilterIntent` and profile entities.
- `Tests`: Xcode unit tests that never target the real `com.apple.dock` domain.
- `Design`: source SVG for the original DockMode icon.

## Distribution and releases (without an Apple Developer account)

DockMode uses these identifiers:

- Application: `fr.wiselaunch.DockMode`
- Focus extension: `fr.wiselaunch.DockMode.FocusExtension`
- App Group: `group.fr.wiselaunch.DockMode`

The current release model is deliberately independent of the Apple Developer Program:

1. Update `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, and `RELEASE_NOTES.md`.
2. Build the universal application and create a DMG with the commands in [Local installation (unsigned development build)](#local-installation-unsigned-development-build).
3. Create a GitHub Release and attach the new `DockMode-<version>.dmg` file.
4. Tell existing users to download that DMG, replace DockMode in **Applications**, and approve the launch again if macOS displays a security warning.

Each release therefore needs a new DMG (or another archive containing the app), but it does not need to be submitted to the Mac App Store or signed with a paid Apple account. GitHub hosts the file; it does not sign the application on Apple’s behalf.

The repository also contains `.github/workflows/release.yml` as an optional template for a future Developer ID/notarized pipeline. It is not required for the no-account workflow described above. The current supported update path is manual DMG replacement; the Sparkle updater remains optional and must not be presented as a silent, Gatekeeper-free update mechanism for unsigned builds.

## Privacy

Profiles and Focus activation requests stay in the local App Group container. DockMode uses `OSLog` for local diagnostics and sends no telemetry. Logs intentionally avoid full home-directory paths.

## Français

DockMode permet de créer plusieurs profils de Dock nommés et colorés. Chaque profil mémorise uniquement les applications épinglées, leur ordre et les séparateurs. Les dossiers, applications récentes et autres réglages restent intacts. Les applications ouvertes ne sont jamais lancées ni fermées lors d'un changement de profil.

La distribution publique actuelle ne dépend pas d'un compte Apple Developer payant. Chaque version est publiée manuellement comme DMG dans une GitHub Release ; les utilisateurs remplacent l'application installée et peuvent devoir l'autoriser une première fois dans le Finder ou dans **Réglages Système → Confidentialité et sécurité**. Le dépôt conserve un workflow optionnel pour une future distribution signée, mais ce workflow n'est pas nécessaire pour publier les versions sans compte Apple.

## License

DockMode is released under the [MIT License](LICENSE).
