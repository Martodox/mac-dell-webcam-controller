import Foundation

public enum FieldOfView: Int, Codable, CaseIterable, Sendable {
    case narrow = 65
    case medium = 78
    case wide = 90
}

/// UVC power line frequency values.
public enum AntiFlicker: Int, Codable, CaseIterable, Sendable {
    case hz50 = 1
    case hz60 = 2
}

public enum TrackingSensitivity: UInt8, Codable, CaseIterable, Sendable {
    case normal = 1
    case fast = 2
}

public enum FrameSize: UInt8, Codable, CaseIterable, Sendable {
    case standard = 1
    case narrow = 2
}

/// Everything the configurator controls. Defaults match DDPM's "Default" preset.
public struct CameraSettings: Codable, Equatable, Sendable {
    public var zoom = 100
    public var pan = 0
    public var tilt = 0
    public var autoFocus = true
    public var focus = 100
    /// UVC AE priority: true lets exposure lower the frame rate, false holds the frame rate.
    public var exposurePriority = true
    public var antiFlicker = AntiFlicker.hz60

    public var hdr = false
    public var autoWhiteBalance = true
    public var whiteBalance = 5000
    public var brightness = 128
    public var contrast = 128
    public var saturation = 128
    public var sharpness = 128

    public var fieldOfView = FieldOfView.wide
    public var autoFraming = false
    public var cameraTransition = true
    public var trackingSensitivity = TrackingSensitivity.normal
    public var frameSize = FrameSize.standard

    public init() {}

    /// One independently writable setting. Order of `allCases` is the order a full apply uses:
    /// auto modes before the manual values they gate, FOV before zoom/pan which it resets.
    public enum Field: CaseIterable, Sendable {
        case antiFlicker, exposurePriority
        case autoWhiteBalance, whiteBalance, brightness, contrast, saturation, sharpness, hdr
        case fieldOfView, autoFraming, cameraTransition, trackingSensitivity, frameSize
        case autoFocus, focus
        case zoom, panTilt
    }

    // Decode field by field so settings files from older versions keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CameraSettings()
        zoom = try c.decodeIfPresent(Int.self, forKey: .zoom) ?? d.zoom
        pan = try c.decodeIfPresent(Int.self, forKey: .pan) ?? d.pan
        tilt = try c.decodeIfPresent(Int.self, forKey: .tilt) ?? d.tilt
        autoFocus = try c.decodeIfPresent(Bool.self, forKey: .autoFocus) ?? d.autoFocus
        focus = try c.decodeIfPresent(Int.self, forKey: .focus) ?? d.focus
        exposurePriority = try c.decodeIfPresent(Bool.self, forKey: .exposurePriority) ?? d.exposurePriority
        antiFlicker = try c.decodeIfPresent(AntiFlicker.self, forKey: .antiFlicker) ?? d.antiFlicker
        hdr = try c.decodeIfPresent(Bool.self, forKey: .hdr) ?? d.hdr
        autoWhiteBalance = try c.decodeIfPresent(Bool.self, forKey: .autoWhiteBalance) ?? d.autoWhiteBalance
        whiteBalance = try c.decodeIfPresent(Int.self, forKey: .whiteBalance) ?? d.whiteBalance
        brightness = try c.decodeIfPresent(Int.self, forKey: .brightness) ?? d.brightness
        contrast = try c.decodeIfPresent(Int.self, forKey: .contrast) ?? d.contrast
        saturation = try c.decodeIfPresent(Int.self, forKey: .saturation) ?? d.saturation
        sharpness = try c.decodeIfPresent(Int.self, forKey: .sharpness) ?? d.sharpness
        fieldOfView = try c.decodeIfPresent(FieldOfView.self, forKey: .fieldOfView) ?? d.fieldOfView
        autoFraming = try c.decodeIfPresent(Bool.self, forKey: .autoFraming) ?? d.autoFraming
        cameraTransition = try c.decodeIfPresent(Bool.self, forKey: .cameraTransition) ?? d.cameraTransition
        trackingSensitivity = try c.decodeIfPresent(TrackingSensitivity.self, forKey: .trackingSensitivity)
            ?? d.trackingSensitivity
        frameSize = try c.decodeIfPresent(FrameSize.self, forKey: .frameSize) ?? d.frameSize
    }
}
