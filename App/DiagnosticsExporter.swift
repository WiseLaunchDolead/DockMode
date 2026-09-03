import AppKit
import Foundation
import UniformTypeIdentifiers

enum DiagnosticsExporter {
    @MainActor
    static func export() async throws -> URL? {
        let panel = NSSavePanel()
        panel.title = String(localized: "Export DockMode Logs")
        panel.nameFieldStringValue = "DockMode.log"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destination = panel.url else { return nil }

        let data = try await Task.detached(priority: .utility) {
            try collectLogs()
        }.value
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private static func collectLogs() throws -> Data {
        let process = Process()
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockMode-Logs-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let output = try FileHandle(forWritingTo: temporaryURL)
        defer { try? output.close() }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "show",
            "--style", "compact",
            "--last", "1d",
            "--predicate", "subsystem BEGINSWITH \"fr.wiselaunch.DockMode\""
        ]
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()
        try output.synchronize()
        let outputData = try Data(contentsOf: temporaryURL)
        guard process.terminationStatus == 0 else {
            let message = String(data: outputData, encoding: .utf8) ?? ""
            throw DiagnosticsExportError.commandFailed(message)
        }

        let raw = String(data: outputData, encoding: .utf8) ?? ""
        let redacted = raw.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        return Data(redacted.utf8)
    }
}

private enum DiagnosticsExportError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(message):
            let format = String(localized: "The log export failed: %@")
            return String(format: format, message)
        }
    }
}
