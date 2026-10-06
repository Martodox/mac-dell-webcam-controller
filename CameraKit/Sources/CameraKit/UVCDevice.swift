import Foundation
import IOKit
import IOKit.usb
import os

let log = Logger(subsystem: "club.freediver.dell-camera", category: "uvc")

/// UVC 1.5 class-specific request codes (bRequest).
public enum UVCRequest: UInt8, Sendable {
    case setCur = 0x01
    case getCur = 0x81
    case getMin = 0x82
    case getMax = 0x83
    case getRes = 0x84
    case getLen = 0x85
    case getInfo = 0x86
    case getDef = 0x87
}

public struct UVCError: Error, CustomStringConvertible {
    public let code: kern_return_t
    public let context: String

    public var description: String {
        String(format: "%@ failed (0x%08x)", context, UInt32(bitPattern: code))
    }
}

// IOUSBLib UUIDs are C macros, which Swift does not import.
private let kUSBDeviceUserClientTypeID = CFUUIDGetConstantUUIDWithBytes(
    nil, 0x9d, 0xc7, 0xb7, 0x80, 0x9e, 0xc0, 0x11, 0xD4, 0xa5, 0x4f, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)
private let kCFPlugInInterfaceID = CFUUIDGetConstantUUIDWithBytes(
    nil, 0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4, 0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F)
private let kUSBDeviceInterfaceID182 = CFUUIDGetConstantUUIDWithBytes(
    nil, 0x15, 0x2f, 0xc4, 0x96, 0x48, 0x91, 0x11, 0xD5, 0x9d, 0x52, 0x00, 0x0a, 0x27, 0x80, 0x1e, 0x86)

private typealias DeviceInterface = UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface182>?>

/// Talks to the WB7022 VideoControl interface through control requests on the default pipe.
/// The device is never opened exclusively, so it keeps working while another app streams video.
public final class UVCDevice: @unchecked Sendable {
    public static let vendorID = 0x413C
    public static let productID = 0xC015
    /// bInterfaceNumber of the VideoControl interface.
    static let videoControlInterface: UInt8 = 0

    private let service: io_service_t
    private let device: DeviceInterface
    private let lock = NSLock()
    private var rangeCache: [UVCControl: ControlRange] = [:]

    public static func matchingDictionary() -> NSMutableDictionary {
        let dict = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        dict["idVendor"] = vendorID
        dict["idProduct"] = productID
        return dict
    }

    /// Opens the first connected WB7022, if any.
    public static func first() -> UVCDevice? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matchingDictionary())
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        do {
            return try UVCDevice(service: service)
        } catch {
            log.error("Opening camera failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    public init(service: io_service_t) throws {
        var plugin: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0
        let kr = IOCreatePlugInInterfaceForService(
            service, kUSBDeviceUserClientTypeID, kCFPlugInInterfaceID, &plugin, &score)
        guard kr == KERN_SUCCESS, let plugin, let pluginInterface = plugin.pointee?.pointee else {
            throw UVCError(code: kr, context: "IOCreatePlugInInterfaceForService")
        }
        defer { _ = pluginInterface.Release(plugin) }

        var raw: LPVOID?
        let hr = pluginInterface.QueryInterface(plugin, CFUUIDGetUUIDBytes(kUSBDeviceInterfaceID182), &raw)
        guard hr == S_OK, let raw else {
            throw UVCError(code: hr, context: "QueryInterface(IOUSBDeviceInterface182)")
        }
        IOObjectRetain(service)
        self.service = service
        self.device = raw.assumingMemoryBound(to: UnsafeMutablePointer<IOUSBDeviceInterface182>?.self)
    }

    deinit {
        _ = device.pointee?.pointee.Release(device)
        IOObjectRelease(service)
    }

    // MARK: Raw requests

    /// Issues one class-specific request to `unit`/`selector` on the VideoControl interface.
    public func request(_ request: UVCRequest, unit: UInt8, selector: UInt8, data: [UInt8]) throws -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }
        guard let interface = device.pointee?.pointee else {
            throw UVCError(code: kIOReturnNoDevice, context: "DeviceRequest")
        }
        var buffer = data
        let isSet = request == .setCur
        let done: UInt32 = try buffer.withUnsafeMutableBytes { bytes in
            var req = IOUSBDevRequestTO(
                bmRequestType: isSet ? 0x21 : 0xA1,
                bRequest: request.rawValue,
                wValue: UInt16(selector) << 8,
                wIndex: UInt16(unit) << 8 | UInt16(Self.videoControlInterface),
                wLength: UInt16(bytes.count),
                pData: bytes.baseAddress,
                wLenDone: 0,
                noDataTimeout: 1000,
                completionTimeout: 1000)
            let kr = interface.DeviceRequestTO(device, &req)
            guard kr == kIOReturnSuccess else {
                throw UVCError(
                    code: kr,
                    context: String(format: "Request 0x%02x unit %d selector 0x%02x", request.rawValue, unit, selector))
            }
            return req.wLenDone
        }
        return Array(buffer.prefix(Int(done)))
    }

    public func get(_ request: UVCRequest, unit: UInt8, selector: UInt8, length: Int) throws -> [UInt8] {
        try self.request(request, unit: unit, selector: selector, data: [UInt8](repeating: 0, count: length))
    }

    public func setCur(unit: UInt8, selector: UInt8, data: [UInt8]) throws {
        _ = try request(.setCur, unit: unit, selector: selector, data: data)
    }

    // MARK: Standard controls

    public func read(_ control: UVCControl, _ request: UVCRequest = .getCur) throws -> Int {
        control.decode(try get(request, unit: control.unit, selector: control.selector, length: control.size))
    }

    public func write(_ control: UVCControl, _ value: Int) throws {
        try setCur(unit: control.unit, selector: control.selector, data: control.encode(value))
    }

    /// Device-reported range, cached for the lifetime of this connection.
    public func range(_ control: UVCControl) throws -> ControlRange {
        if let cached = cachedRange(control) { return cached }
        let range = ControlRange(
            min: try read(control, .getMin),
            max: try read(control, .getMax),
            step: max(1, (try? read(control, .getRes)) ?? 1),
            defaultValue: try read(control, .getDef))
        lock.lock()
        rangeCache[control] = range
        lock.unlock()
        return range
    }

    private func cachedRange(_ control: UVCControl) -> ControlRange? {
        lock.lock()
        defer { lock.unlock() }
        return rangeCache[control]
    }

    public func readPanTilt(_ request: UVCRequest = .getCur) throws -> (pan: Int, tilt: Int) {
        let c = UVCControl.panTilt
        let bytes = try get(request, unit: c.unit, selector: c.selector, length: c.size)
        guard bytes.count == 8 else { throw UVCError(code: kIOReturnUnderrun, context: "Pan/tilt read") }
        return (UVCControl.decodeInt32(bytes[0..<4]), UVCControl.decodeInt32(bytes[4..<8]))
    }

    public func writePanTilt(pan: Int, tilt: Int) throws {
        let c = UVCControl.panTilt
        try setCur(unit: c.unit, selector: c.selector,
                   data: UVCControl.encodeInt32(pan) + UVCControl.encodeInt32(tilt))
    }

    public func panTiltRange() throws -> (pan: ControlRange, tilt: ControlRange) {
        let lo = try readPanTilt(.getMin), hi = try readPanTilt(.getMax), def = try readPanTilt(.getDef)
        let res = (try? readPanTilt(.getRes)) ?? (pan: 3600, tilt: 3600)
        return (ControlRange(min: lo.pan, max: hi.pan, step: max(1, res.pan), defaultValue: def.pan),
                ControlRange(min: lo.tilt, max: hi.tilt, step: max(1, res.tilt), defaultValue: def.tilt))
    }

    // MARK: Dell extension unit

    public func send(_ command: VendorCommand) throws {
        try setCur(unit: DellXU.unit, selector: DellXU.commandSelector, data: command.payload)
    }
}

/// Watches for the WB7022 being plugged in or removed. Callbacks arrive on the main run loop.
public final class UVCDeviceMonitor {
    public enum Event {
        case attached(UVCDevice)
        case detached
    }

    private let handler: (Event) -> Void
    private var port: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0

    public init(handler: @escaping (Event) -> Void) {
        self.handler = handler
    }

    deinit { stop() }

    /// Starts monitoring. A camera that is already connected is reported as `.attached` immediately.
    public func start() {
        guard port == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        CFRunLoopAddSource(
            CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        let context = Unmanaged.passUnretained(self).toOpaque()

        IOServiceAddMatchingNotification(
            port, kIOFirstMatchNotification, UVCDevice.matchingDictionary(),
            { context, iterator in
                Unmanaged<UVCDeviceMonitor>.fromOpaque(context!).takeUnretainedValue().drain(iterator, attached: true)
            }, context, &addedIterator)
        IOServiceAddMatchingNotification(
            port, kIOTerminatedNotification, UVCDevice.matchingDictionary(),
            { context, iterator in
                Unmanaged<UVCDeviceMonitor>.fromOpaque(context!).takeUnretainedValue().drain(iterator, attached: false)
            }, context, &removedIterator)

        drain(addedIterator, attached: true)
        drain(removedIterator, attached: false, notify: false)
    }

    public func stop() {
        if addedIterator != 0 { IOObjectRelease(addedIterator); addedIterator = 0 }
        if removedIterator != 0 { IOObjectRelease(removedIterator); removedIterator = 0 }
        if let port { IONotificationPortDestroy(port) }
        port = nil
    }

    private func drain(_ iterator: io_iterator_t, attached: Bool, notify: Bool = true) {
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            guard notify else { continue }
            if attached {
                do {
                    handler(.attached(try UVCDevice(service: service)))
                } catch {
                    log.error("Attach failed: \(String(describing: error), privacy: .public)")
                }
            } else {
                handler(.detached)
            }
        }
    }
}
