import Foundation
import ServiceManagement

enum LaunchAtLoginState: Equatable {
    case unknown
    case enabled
    case requiresApproval
    case unavailable
    case failed(String)
}

struct LaunchAtLoginManager {
    var currentState: LaunchAtLoginState {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        case .notRegistered: .unknown
        @unknown default: .unknown
        }
    }

    func enable() -> LaunchAtLoginState {
        let service = SMAppService.mainApp
        if service.status == .enabled { return .enabled }

        do {
            try service.register()
            return currentState
        } catch {
            if service.status == .requiresApproval { return .requiresApproval }
            return .failed(error.localizedDescription)
        }
    }
}
