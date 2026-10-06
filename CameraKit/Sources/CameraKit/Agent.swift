import Foundation

/// Identifiers shared by the preference pane and the Dell Camera Agent app.
public enum Agent {
    public static let bundleIdentifier = "club.freediver.dell-camera-agent"
    /// launchd label of the login agent. launchd exports it as XPC_SERVICE_NAME.
    public static let launchdLabel = "club.freediver.dell-camera-agent"
    public static let appName = "Dell Camera Agent.app"
    public static let executableName = "DellCameraAgent"
    /// Opening this URL with the agent shows the preview window.
    public static let previewURL = URL(string: "dell-camera-agent://preview")!
}
