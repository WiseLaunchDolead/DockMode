import Combine
import DockModeCore
import Foundation
import OSLog

enum ProfileSwitchSource {
    case manual
    case focus
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var document: ProfilesDocument
    @Published private(set) var applicationCatalog: [ApplicationReference] = []
    @Published private(set) var onboardingItems: [DockItem] = []
    @Published private(set) var missingApplications: [ApplicationReference] = []
    @Published private(set) var isSwitching = false
    @Published var isPresentingNewProfile = false
    @Published var alertMessage: String?
    @Published private(set) var launchAtLoginState: LaunchAtLoginState = .unknown

    private let profileStore: ProfileStore
    private let focusRequestStore: FocusRequestStore
    private let dockRepository: DockRepository
    private let launchAtLoginManager: LaunchAtLoginManager
    private let logger = Logger(subsystem: "fr.wiselaunch.DockMode", category: "AppModel")

    private var monitorTimer: Timer?
    private var focusObserver: FocusRequestObserver?
    private var focusDebounceTask: Task<Void, Never>?
    private var expectedDockFingerprint = ""

    var profiles: [Profile] { document.profiles }
    var needsOnboarding: Bool { document.profiles.isEmpty }

    var activeProfile: Profile? {
        guard let activeProfileID = document.activeProfileID else { return nil }
        return document.profiles.first(where: { $0.id == activeProfileID })
    }

    init(
        profileStore: ProfileStore = ProfileStore(),
        focusRequestStore: FocusRequestStore = FocusRequestStore(),
        dockRepository: DockRepository = DockRepository(),
        launchAtLoginManager: LaunchAtLoginManager = LaunchAtLoginManager()
    ) {
        self.profileStore = profileStore
        self.focusRequestStore = focusRequestStore
        self.dockRepository = dockRepository
        self.launchAtLoginManager = launchAtLoginManager

        do {
            document = try profileStore.load()
        } catch {
            document = ProfilesDocument()
            alertMessage = error.localizedDescription
        }

        absorbCurrentDockAtLaunch()
    }

    func start() {
        guard monitorTimer == nil else { return }

        if !needsOnboarding {
            launchAtLoginState = launchAtLoginManager.enable()
        }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollDock() }
        }
        RunLoop.main.add(timer, forMode: .common)
        monitorTimer = timer

        focusObserver = FocusRequestObserver { [weak self] in
            self?.schedulePendingFocusRequest()
        }
        focusObserver?.start()
        schedulePendingFocusRequest()

        Task {
            let applications = await Task.detached(priority: .utility) {
                ApplicationCatalog.discover()
            }.value
            applicationCatalog = applications
        }
    }

    func createProfile(name: String, color: ProfileColor, items: [DockItem]) throws {
        let normalizedName = try ProfileValidator.validateName(name, excluding: nil, in: profiles)
        let profile = Profile(name: normalizedName, color: color, items: deduplicated(items))
        let previousDocument = document
        let previousMissingApplications = missingApplications
        let previousFingerprint = expectedDockFingerprint
        document.profiles.append(profile)

        do {
            if previousDocument.profiles.isEmpty {
                let result = try dockRepository.apply(profile.items)
                document.activeProfileID = profile.id
                refreshResolvedItems(for: profile.id, with: result.appliedItems)
                missingApplications = result.missingApplications
                expectedDockFingerprint = dockRepository.codec.fingerprint(result.appliedItems)
                try persist()
            } else {
                try persist()
                try switchProfile(to: profile.id, source: .manual)
            }
            launchAtLoginState = launchAtLoginManager.enable()
        } catch {
            if previousDocument.profiles.isEmpty,
               let rollback = try? dockRepository.apply(onboardingItems) {
                missingApplications = rollback.missingApplications
                expectedDockFingerprint = dockRepository.codec.fingerprint(rollback.appliedItems)
            } else {
                missingApplications = previousMissingApplications
                expectedDockFingerprint = previousFingerprint
            }
            document = previousDocument
            try? persist()
            throw error
        }
    }

    func updateProfile(id: UUID, name: String, color: ProfileColor, items: [DockItem]) throws {
        let normalizedName = try ProfileValidator.validateName(name, excluding: id, in: profiles)
        guard let index = document.profiles.firstIndex(where: { $0.id == id }) else { return }
        let previousDocument = document

        var updated = document.profiles[index]
        updated.name = normalizedName
        updated.color = color
        updated.items = deduplicated(items)
        updated.updatedAt = Date()

        if DockLayoutSavePolicy.action(profileID: id, activeProfileID: document.activeProfileID)
            == .applyToDock {
            let previousMissingApplications = missingApplications
            let previousFingerprint = expectedDockFingerprint
            do {
                if dockRepository.codec.fingerprint(updated.items)
                    == dockRepository.codec.fingerprint(document.profiles[index].items) {
                    document.profiles[index] = updated
                } else {
                    let result = try dockRepository.apply(updated.items)
                    document.profiles[index] = updated
                    refreshResolvedItems(for: id, with: result.appliedItems)
                    missingApplications = result.missingApplications
                    expectedDockFingerprint = dockRepository.codec.fingerprint(result.appliedItems)
                }
                try persist()
            } catch {
                if dockRepository.codec.fingerprint(updated.items)
                    != dockRepository.codec.fingerprint(previousDocument.profiles[index].items),
                   let rollback = try? dockRepository.apply(previousDocument.profiles[index].items) {
                    missingApplications = rollback.missingApplications
                    expectedDockFingerprint = dockRepository.codec.fingerprint(rollback.appliedItems)
                } else {
                    missingApplications = previousMissingApplications
                    expectedDockFingerprint = previousFingerprint
                }
                document = previousDocument
                throw error
            }
        } else {
            document.profiles[index] = updated
            do {
                try persist()
            } catch {
                document = previousDocument
                throw error
            }
        }
    }

    func saveDockLayout(profileID: UUID, items: [DockItem]) throws {
        guard let profile = document.profiles.first(where: { $0.id == profileID }) else { return }
        try updateProfile(
            id: profileID,
            name: profile.name,
            color: profile.color,
            items: items
        )
    }

    func renameProfile(id: UUID, name: String) throws {
        guard let profile = document.profiles.first(where: { $0.id == id }) else { return }
        try updateProfile(id: id, name: name, color: profile.color, items: profile.items)
    }

    func recolorProfile(id: UUID, color: ProfileColor) throws {
        guard let profile = document.profiles.first(where: { $0.id == id }) else { return }
        try updateProfile(id: id, name: profile.name, color: color, items: profile.items)
    }

    func deleteProfile(id: UUID) throws {
        guard profiles.count > 1, document.activeProfileID != id else { return }
        document.profiles.removeAll(where: { $0.id == id })
        if document.focusState.profileBeforeFocusID == id {
            document.focusState.profileBeforeFocusID = nil
        }
        try persist()
    }

    func switchProfile(to profileID: UUID, source: ProfileSwitchSource = .manual) throws {
        guard !isSwitching,
              document.activeProfileID != profileID,
              let targetIndex = document.profiles.firstIndex(where: { $0.id == profileID }) else {
            return
        }

        isSwitching = true
        defer { isSwitching = false }

        captureCurrentDockInActiveProfile()
        try persist()

        let sourceDocument = document
        let sourceProfile = activeProfile
        let sourceMissingApplications = missingApplications
        let sourceFingerprint = expectedDockFingerprint
        let target = document.profiles[targetIndex]
        do {
            let result = try dockRepository.apply(target.items)
            document.activeProfileID = profileID
            refreshResolvedItems(for: profileID, with: result.appliedItems)
            missingApplications = result.missingApplications
            expectedDockFingerprint = dockRepository.codec.fingerprint(result.appliedItems)
            try persist()
        } catch {
            if let sourceProfile,
               let rollback = try? dockRepository.apply(sourceProfile.items) {
                missingApplications = rollback.missingApplications
                expectedDockFingerprint = dockRepository.codec.fingerprint(rollback.appliedItems)
            } else {
                missingApplications = sourceMissingApplications
                expectedDockFingerprint = sourceFingerprint
            }
            document = sourceDocument
            try? persist()
            throw error
        }

        logger.info("Switched Dock profile from \(String(describing: source), privacy: .public)")
    }

    func presentError(_ error: Error) {
        logger.error("\(error.localizedDescription, privacy: .public)")
        alertMessage = error.localizedDescription
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginState = launchAtLoginManager.currentState
    }

    private func absorbCurrentDockAtLaunch() {
        do {
            let observed = try dockRepository.currentItems()
            onboardingItems = observed
            expectedDockFingerprint = dockRepository.codec.fingerprint(observed)

            if document.activeProfileID == nil, let firstProfile = document.profiles.first {
                document.activeProfileID = firstProfile.id
            }
            guard let activeID = document.activeProfileID,
                  let index = document.profiles.firstIndex(where: { $0.id == activeID }) else {
                return
            }

            let existing = document.profiles[index].items
            let missing = dockRepository.missingApplications(in: existing)
            let missingKeys = Set(missing.map(\.stableKey))
            document.profiles[index].items = DockItemReconciler.reconcile(
                observed: observed,
                preservingMissingFrom: existing,
                missingApplicationKeys: missingKeys
            )
            document.profiles[index].updatedAt = Date()
            missingApplications = missing
            try persist()
        } catch {
            logger.error("Could not absorb current Dock: \(error.localizedDescription, privacy: .public)")
            if document.profiles.isEmpty {
                alertMessage = error.localizedDescription
            }
        }
    }

    private func pollDock() {
        guard !isSwitching, let activeID = document.activeProfileID else { return }
        do {
            let observed = try dockRepository.currentItems()
            let fingerprint = dockRepository.codec.fingerprint(observed)
            guard fingerprint != expectedDockFingerprint,
                  let index = document.profiles.firstIndex(where: { $0.id == activeID }) else {
                return
            }

            let existing = document.profiles[index].items
            let missingKeys = Set(missingApplications.map(\.stableKey))
            document.profiles[index].items = DockItemReconciler.reconcile(
                observed: observed,
                preservingMissingFrom: existing,
                missingApplicationKeys: missingKeys
            )
            document.profiles[index].updatedAt = Date()
            expectedDockFingerprint = fingerprint
            try persist()
            logger.debug("Saved a manual Dock change in the active profile")
        } catch {
            logger.error("Dock monitor failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func captureCurrentDockInActiveProfile() {
        guard let activeID = document.activeProfileID,
              let index = document.profiles.firstIndex(where: { $0.id == activeID }),
              let observed = try? dockRepository.currentItems() else {
            return
        }
        let existing = document.profiles[index].items
        let missingKeys = Set(missingApplications.map(\.stableKey))
        document.profiles[index].items = DockItemReconciler.reconcile(
            observed: observed,
            preservingMissingFrom: existing,
            missingApplicationKeys: missingKeys
        )
        document.profiles[index].updatedAt = Date()
        expectedDockFingerprint = dockRepository.codec.fingerprint(observed)
    }

    private func refreshResolvedItems(for profileID: UUID, with appliedItems: [DockItem]) {
        guard let index = document.profiles.firstIndex(where: { $0.id == profileID }) else { return }
        let resolvedByID = Dictionary(uniqueKeysWithValues: appliedItems.map { ($0.id, $0) })
        document.profiles[index].items = document.profiles[index].items.map { resolvedByID[$0.id] ?? $0 }
        document.profiles[index].updatedAt = Date()
    }

    private func deduplicated(_ items: [DockItem]) -> [DockItem] {
        var seenApplications = Set<String>()
        return items.filter { item in
            guard case let .application(reference) = item.content else { return true }
            return seenApplications.insert(reference.stableKey).inserted
        }
    }

    private func schedulePendingFocusRequest() {
        focusDebounceTask?.cancel()
        focusDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.handlePendingFocusRequest()
        }
    }

    private func handlePendingFocusRequest() {
        do {
            guard let request = try focusRequestStore.load(),
                  request.id != document.focusState.lastHandledRequestID else {
                return
            }

            let previousFocusState = document.focusState

            do {
                let requestedProfileID = FocusAutomationReducer.apply(
                    request,
                    to: &document.focusState,
                    currentActiveProfileID: document.activeProfileID
                )
                try persist()
                if let requestedProfileID {
                    guard profiles.contains(where: { $0.id == requestedProfileID }) else {
                        throw FocusAutomationError.profileUnavailable
                    }
                    try switchProfile(to: requestedProfileID, source: .focus)
                }
            } catch {
                document.focusState = previousFocusState
                document.focusState.lastHandledRequestID = request.id
                try? persist()
                throw error
            }
        } catch {
            presentError(error)
        }
    }

    private func persist() throws {
        try profileStore.save(document)
    }
}
