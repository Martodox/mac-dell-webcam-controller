import Foundation

/// A standard UVC control: terminal/unit ID, control selector and wire size (little endian).
public struct UVCControl: Hashable, Sendable {
    public let unit: UInt8
    public let selector: UInt8
    public let size: Int
    public let isSigned: Bool

    init(unit: UInt8, selector: UInt8, size: Int, isSigned: Bool = false) {
        self.unit = unit
        self.selector = selector
        self.size = size
        self.isSigned = isSigned
    }

    // Unit IDs from the WB7022 configuration descriptor.
    static let cameraTerminal: UInt8 = 1
    static let processingUnit: UInt8 = 3

    // Camera Terminal (UVC 1.5 §4.2.2.1)
    public static let aePriority = UVCControl(unit: cameraTerminal, selector: 0x03, size: 1)
    public static let focus = UVCControl(unit: cameraTerminal, selector: 0x06, size: 2)
    public static let autoFocus = UVCControl(unit: cameraTerminal, selector: 0x08, size: 1)
    public static let zoom = UVCControl(unit: cameraTerminal, selector: 0x0B, size: 2)
    public static let panTilt = UVCControl(unit: cameraTerminal, selector: 0x0D, size: 8)

    // Processing Unit (UVC 1.5 §4.2.2.3)
    public static let brightness = UVCControl(unit: processingUnit, selector: 0x02, size: 2, isSigned: true)
    public static let contrast = UVCControl(unit: processingUnit, selector: 0x03, size: 2)
    public static let powerLineFrequency = UVCControl(unit: processingUnit, selector: 0x05, size: 1)
    public static let saturation = UVCControl(unit: processingUnit, selector: 0x07, size: 2)
    public static let sharpness = UVCControl(unit: processingUnit, selector: 0x08, size: 2)
    public static let whiteBalance = UVCControl(unit: processingUnit, selector: 0x0A, size: 2)
    public static let autoWhiteBalance = UVCControl(unit: processingUnit, selector: 0x0B, size: 1)

    func encode(_ value: Int) -> [UInt8] {
        (0..<size).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
    }

    func decode(_ bytes: [UInt8]) -> Int {
        var value = 0
        for (i, byte) in bytes.prefix(size).enumerated() { value |= Int(byte) << (8 * i) }
        if isSigned, size < 8, value & (1 << (8 * size - 1)) != 0 { value -= 1 << (8 * size) }
        return value
    }

    static func encodeInt32(_ value: Int) -> [UInt8] {
        withUnsafeBytes(of: Int32(clamping: value).littleEndian, Array.init)
    }

    static func decodeInt32(_ bytes: ArraySlice<UInt8>) -> Int {
        Int(bytes.reversed().reduce(Int32(0)) { $0 << 8 | Int32($1) })
    }
}

public struct ControlRange: Equatable, Sendable {
    public var min: Int
    public var max: Int
    public var step: Int
    public var defaultValue: Int

    public init(min: Int, max: Int, step: Int = 1, defaultValue: Int) {
        self.min = min
        self.max = max
        self.step = step
        self.defaultValue = defaultValue
    }

    public func clamp(_ value: Int) -> Int { Swift.min(max, Swift.max(min, value)) }

    /// Ranges DDPM ships for the WB7022, used until the device reports its own.
    public static let fallback: [UVCControl: ControlRange] = [
        .zoom: ControlRange(min: 100, max: 500, defaultValue: 100),
        .focus: ControlRange(min: 100, max: 600, defaultValue: 100),
        .whiteBalance: ControlRange(min: 2800, max: 7500, step: 50, defaultValue: 5000),
        .brightness: ControlRange(min: 0, max: 255, defaultValue: 128),
        .contrast: ControlRange(min: 0, max: 255, defaultValue: 128),
        .saturation: ControlRange(min: 0, max: 255, defaultValue: 128),
        .sharpness: ControlRange(min: 0, max: 255, defaultValue: 128),
    ]
    public static let panTiltFallback = ControlRange(min: -131072, max: 131072, step: 3600, defaultValue: 0)
}

/// One write to the Dell vendor command control.
public struct VendorCommand: Equatable, Sendable {
    /// The value as DDPM stores it, e.g. `0x005A0110FF` for FOV 90°.
    public let value: UInt64

    /// DDPM copies the value out of a `long`, so the bytes go out little endian:
    /// `0x005A0110FF` → `FF 10 01 5A 00 00 00 00`.
    var payload: [UInt8] {
        withUnsafeBytes(of: value.littleEndian, Array.init)
    }
}

/// Dell vendor extension unit 6 (GUID 23e49ed0-1178-4f31-ae52-d2fb8a8d3b48). Every feature
/// below is a command written to selector 1, recovered from DDPM's feature table and its
/// DDPM_Camera_Settings.json. Byte 0 is always 0xFF, byte 1 the command, then arguments.
public enum DellXU {
    public static let unit: UInt8 = 0x06
    public static let commandSelector: UInt8 = 0x01
    /// GET_LEN of the command control.
    static let commandLength = 8

    enum Command: UInt64 {
        case fieldOfView = 0x10
        case hdr = 0x11
        case framing = 0x14
    }

    enum FramingFeature: UInt64 {
        case autoFraming = 0x01
        case cameraTransition = 0x10
        case trackingSensitivity = 0x11
        case frameSize = 0x12
    }

    private static func command(_ command: Command, _ arguments: UInt64) -> VendorCommand {
        VendorCommand(value: arguments << 16 | command.rawValue << 8 | 0xFF)
    }

    public static func fieldOfView(_ fov: FieldOfView) -> VendorCommand {
        command(.fieldOfView, UInt64(fov.rawValue) << 8 | 0x01)
    }

    public static func hdr(_ on: Bool) -> VendorCommand {
        command(.hdr, on ? 1 : 0)
    }

    public static func autoFraming(_ on: Bool) -> VendorCommand {
        framing(.autoFraming, on ? 1 : 0)
    }

    public static func cameraTransition(_ on: Bool) -> VendorCommand {
        framing(.cameraTransition, on ? 1 : 0)
    }

    public static func trackingSensitivity(_ value: TrackingSensitivity) -> VendorCommand {
        framing(.trackingSensitivity, UInt64(value.rawValue))
    }

    public static func frameSize(_ value: FrameSize) -> VendorCommand {
        framing(.frameSize, UInt64(value.rawValue))
    }

    private static func framing(_ feature: FramingFeature, _ value: UInt64) -> VendorCommand {
        command(.framing, value << 8 | feature.rawValue)
    }
}
