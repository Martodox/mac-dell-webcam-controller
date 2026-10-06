import Foundation

/// Persisted state shared by the preference pane and the login helper.
public struct StoredState: Codable, Equatable, Sendable {
    public var settings = CameraSettings()
    public var customPresets: [ImagePreset] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = try c.decodeIfPresent(CameraSettings.self, forKey: .settings) ?? CameraSettings()
        customPresets = try c.decodeIfPresent([ImagePreset].self, forKey: .customPresets) ?? []
    }
}

public enum SettingsStore {
    /// `~/Library/Application Support/DellCameraConfigurator`. Resolved from the password
    /// database rather than `NSHomeDirectory()` so the pane (hosted by System Settings) and
    /// the helper agree even if one of them runs containerised.
    public static var directory: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) }
            ?? NSHomeDirectory()
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/DellCameraConfigurator", isDirectory: true)
    }

    public static var stateURL: URL { directory.appendingPathComponent("state.json") }

    /// nil when nothing has been saved yet.
    public static func load() -> StoredState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        do {
            return try JSONDecoder().decode(StoredState.self, from: data)
        } catch {
            log.error("Ignoring unreadable state.json: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    public static func save(_ state: StoredState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: stateURL, options: .atomic)
    }
}
