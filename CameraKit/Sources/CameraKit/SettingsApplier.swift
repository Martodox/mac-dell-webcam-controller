import Foundation

public enum SettingsApplier {
    /// Writes every setting in `Field.allCases` order. Keeps going past failures and
    /// returns a description of each one.
    @discardableResult
    public static func applyAll(_ settings: CameraSettings, to device: UVCDevice) -> [String] {
        var failures: [String] = []
        for field in CameraSettings.Field.allCases {
            do {
                try apply(field, of: settings, to: device)
            } catch {
                failures.append("\(field): \(error)")
            }
        }
        if failures.isEmpty {
            log.info("Applied all camera settings")
        } else {
            log.error("Apply finished with failures: \(failures.joined(separator: "; "), privacy: .public)")
        }
        return failures
    }

    /// Writes one setting. Manual values gated by an auto mode are skipped while that mode is on.
    public static func apply(_ field: CameraSettings.Field, of s: CameraSettings, to device: UVCDevice) throws {
        switch field {
        case .antiFlicker:
            try device.write(.powerLineFrequency, s.antiFlicker.rawValue)
        case .exposurePriority:
            try device.write(.aePriority, s.exposurePriority ? 1 : 0)
        case .autoWhiteBalance:
            try device.write(.autoWhiteBalance, s.autoWhiteBalance ? 1 : 0)
            if !s.autoWhiteBalance { try apply(.whiteBalance, of: s, to: device) }
        case .whiteBalance:
            guard !s.autoWhiteBalance else { return }
            try writeClamped(.whiteBalance, s.whiteBalance, device)
        case .brightness:
            try writeClamped(.brightness, s.brightness, device)
        case .contrast:
            try writeClamped(.contrast, s.contrast, device)
        case .saturation:
            try writeClamped(.saturation, s.saturation, device)
        case .sharpness:
            try writeClamped(.sharpness, s.sharpness, device)
        case .hdr:
            try device.send(DellXU.hdr(s.hdr))
        case .fieldOfView:
            try device.send(DellXU.fieldOfView(s.fieldOfView))
        case .autoFraming:
            try device.send(DellXU.autoFraming(s.autoFraming))
        case .cameraTransition:
            try device.send(DellXU.cameraTransition(s.cameraTransition))
        case .trackingSensitivity:
            try device.send(DellXU.trackingSensitivity(s.trackingSensitivity))
        case .frameSize:
            try device.send(DellXU.frameSize(s.frameSize))
        case .autoFocus:
            try device.write(.autoFocus, s.autoFocus ? 1 : 0)
            if !s.autoFocus { try apply(.focus, of: s, to: device) }
        case .focus:
            guard !s.autoFocus else { return }
            try writeClamped(.focus, s.focus, device)
        case .zoom:
            // Auto framing drives zoom and pan/tilt itself.
            guard !s.autoFraming else { return }
            try writeClamped(.zoom, s.zoom, device)
        case .panTilt:
            guard !s.autoFraming else { return }
            let range = (try? device.panTiltRange())
                ?? (pan: ControlRange.panTiltFallback, tilt: ControlRange.panTiltFallback)
            try device.writePanTilt(pan: range.pan.clamp(s.pan), tilt: range.tilt.clamp(s.tilt))
        }
    }

    private static func writeClamped(_ control: UVCControl, _ value: Int, _ device: UVCDevice) throws {
        let range = (try? device.range(control)) ?? ControlRange.fallback[control]
        try device.write(control, range?.clamp(value) ?? value)
    }

    /// Reads the standard controls back from the camera into `settings`. The Dell vendor
    /// features are write-only, so those fields stay as they are. Used to seed the pane on first launch.
    public static func readBack(into settings: inout CameraSettings, from device: UVCDevice) {
        func value(_ c: UVCControl) -> Int? { try? device.read(c) }
        if let v = value(.zoom) { settings.zoom = v }
        if let pt = try? device.readPanTilt() { settings.pan = pt.pan; settings.tilt = pt.tilt }
        if let v = value(.autoFocus) { settings.autoFocus = v != 0 }
        if let v = value(.focus) { settings.focus = v }
        if let v = value(.aePriority) { settings.exposurePriority = v != 0 }
        if let v = value(.powerLineFrequency), let f = AntiFlicker(rawValue: v) { settings.antiFlicker = f }
        if let v = value(.autoWhiteBalance) { settings.autoWhiteBalance = v != 0 }
        if let v = value(.whiteBalance) { settings.whiteBalance = v }
        if let v = value(.brightness) { settings.brightness = v }
        if let v = value(.contrast) { settings.contrast = v }
        if let v = value(.saturation) { settings.saturation = v }
        if let v = value(.sharpness) { settings.sharpness = v }
    }
}
