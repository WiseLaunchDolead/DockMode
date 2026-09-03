import CoreFoundation
import DockModeCore
import Foundation

private let focusRequestCallback: CFNotificationCallback = { _, observer, _, _, _ in
    guard let observer else { return }
    let requestObserver = Unmanaged<FocusRequestObserver>.fromOpaque(observer).takeUnretainedValue()
    requestObserver.receive()
}

@MainActor
final class FocusRequestObserver {
    private let handler: () -> Void
    private var isStarted = false

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            focusRequestCallback,
            DockModeConstants.focusNotificationName as CFString,
            nil,
            .deliverImmediately
        )
    }

    func stop() {
        guard isStarted else { return }
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(DockModeConstants.focusNotificationName as CFString),
            nil
        )
        isStarted = false
    }

    nonisolated func receive() {
        Task { @MainActor [weak self] in self?.handler() }
    }
}
