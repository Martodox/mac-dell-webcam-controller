import AppKit
import CameraKit

/// Keeps a copy of the bundled Dell Camera Agent in Application Support, opens its preview
/// window, and registers it as a per-user LaunchAgent when automatic re-apply is on.
enum AgentInstaller {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    static var installedApp: URL {
        SettingsStore.directory.appendingPathComponent(Agent.appName, isDirectory: true)
    }

    private static var launchAgentsDirectory: URL {
        SettingsStore.directory
            .deletingLastPathComponent() // Application Support
            .deletingLastPathComponent() // Library
            .appendingPathComponent("LaunchAgents", isDirectory: true)
    }

    static var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(Agent.launchdLabel).plist")
    }

    static var isLoginAgentEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    private static var bundledApp: URL? {
        Bundle(for: DellCameraPane.self).url(forResource: Agent.appName, withExtension: nil)
    }

    private static func executable(in app: URL) -> URL {
        app.appendingPathComponent("Contents/MacOS/\(Agent.executableName)")
    }

    /// Copies the agent out of the pane bundle when missing or outdated.
    /// Returns true when the installed copy changed.
    @discardableResult
    static func installAppIfNeeded() throws -> Bool {
        guard let source = bundledApp else {
            throw Failure(errorDescription: "Dell Camera Agent is missing from the preference pane.")
        }
        let fm = FileManager.default
        if fm.contentsEqual(atPath: executable(in: source).path, andPath: executable(in: installedApp).path) {
            return false
        }
        try fm.createDirectory(at: SettingsStore.directory, withIntermediateDirectories: true)
        if fm.fileExists(atPath: installedApp.path) { try fm.removeItem(at: installedApp) }
        try fm.copyItem(at: source, to: installedApp)
        return true
    }

    static func openPreview() throws {
        if try installAppIfNeeded(), isLoginAgentEnabled { try enableLoginAgent() }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([Agent.previewURL], withApplicationAt: installedApp,
                                configuration: configuration)
    }

    static func enableLoginAgent() throws {
        try installAppIfNeeded()
        try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "Label": Agent.launchdLabel,
            "ProgramArguments": [executable(in: installedApp).path],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Interactive",
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: plistURL, options: .atomic)
        launchctl("bootout", "gui/\(getuid())/\(Agent.launchdLabel)")
        guard launchctl("bootstrap", "gui/\(getuid())", plistURL.path) == 0 else {
            throw Failure(errorDescription: "launchctl could not start Dell Camera Agent.")
        }
    }

    static func disableLoginAgent() throws {
        launchctl("bootout", "gui/\(getuid())/\(Agent.launchdLabel)")
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    /// Updates a running login agent after the pane itself was updated, and removes the
    /// command-line helper that earlier builds installed.
    static func refresh() {
        removeLegacyHelper()
        guard isLoginAgentEnabled, (try? installAppIfNeeded()) == true else { return }
        try? enableLoginAgent()
    }

    private static func removeLegacyHelper() {
        let label = "club.freediver.dell-camera-helper"
        let plist = launchAgentsDirectory.appendingPathComponent("\(label).plist")
        let binary = SettingsStore.directory.appendingPathComponent("dell-camera-helper")
        let fm = FileManager.default
        guard fm.fileExists(atPath: plist.path) || fm.fileExists(atPath: binary.path) else { return }
        launchctl("bootout", "gui/\(getuid())/\(label)")
        try? fm.removeItem(at: plist)
        try? fm.removeItem(at: binary)
    }

    @discardableResult
    private static func launchctl(_ arguments: String...) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
