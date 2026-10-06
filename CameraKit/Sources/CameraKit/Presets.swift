import Foundation

/// A named "look": colour and image settings only. Applying a preset leaves
/// field of view, framing, zoom, pan/tilt and focus untouched.
public struct ImagePreset: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var isBuiltIn: Bool
    public var hdr: Bool
    public var autoWhiteBalance: Bool
    public var whiteBalance: Int
    public var brightness: Int
    public var contrast: Int
    public var saturation: Int
    public var sharpness: Int

    public init(id: String = UUID().uuidString, name: String, isBuiltIn: Bool = false, hdr: Bool,
                autoWhiteBalance: Bool = true, whiteBalance: Int = 5000,
                brightness: Int, contrast: Int, saturation: Int, sharpness: Int) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.hdr = hdr
        self.autoWhiteBalance = autoWhiteBalance
        self.whiteBalance = whiteBalance
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.sharpness = sharpness
    }

    /// Captures the image settings of `settings` as a new custom preset.
    public init(name: String, from settings: CameraSettings) {
        self.init(name: name, hdr: settings.hdr, autoWhiteBalance: settings.autoWhiteBalance,
                  whiteBalance: settings.whiteBalance, brightness: settings.brightness,
                  contrast: settings.contrast, saturation: settings.saturation, sharpness: settings.sharpness)
    }

    public func apply(to settings: inout CameraSettings) {
        settings.hdr = hdr
        settings.autoWhiteBalance = autoWhiteBalance
        settings.whiteBalance = whiteBalance
        settings.brightness = brightness
        settings.contrast = contrast
        settings.saturation = saturation
        settings.sharpness = sharpness
    }

    public func matches(_ settings: CameraSettings) -> Bool {
        var copy = settings
        apply(to: &copy)
        return copy == settings
    }

    public static let fields: [CameraSettings.Field] = [
        .autoWhiteBalance, .whiteBalance, .brightness, .contrast, .saturation, .sharpness, .hdr,
    ]

    /// Values from DDPM's DDPM_Camera_Settings.json for the WB7022.
    public static let builtIns: [ImagePreset] = [
        ImagePreset(id: "default", name: "Default", isBuiltIn: true, hdr: false,
                    brightness: 128, contrast: 128, saturation: 128, sharpness: 128),
        ImagePreset(id: "smooth", name: "Smooth", isBuiltIn: true, hdr: true,
                    brightness: 160, contrast: 128, saturation: 128, sharpness: 0),
        ImagePreset(id: "vibrant", name: "Vibrant", isBuiltIn: true, hdr: true,
                    brightness: 192, contrast: 167, saturation: 152, sharpness: 181),
        ImagePreset(id: "warm", name: "Warm", isBuiltIn: true, hdr: true, whiteBalance: 5950,
                    brightness: 169, contrast: 166, saturation: 134, sharpness: 168),
    ]
}
