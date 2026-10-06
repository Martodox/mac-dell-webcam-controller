import Foundation
import Testing
@testable import CameraKit

@Suite struct ControlEncodingTests {
    @Test func encodesLittleEndian() {
        #expect(UVCControl.whiteBalance.encode(5000) == [0x88, 0x13])
        #expect(UVCControl.autoFocus.encode(1) == [0x01])
    }

    @Test func decodesSignedValues() {
        #expect(UVCControl.brightness.decode([0xFF, 0xFF]) == -1)
        #expect(UVCControl.contrast.decode([0xFF, 0xFF]) == 0xFFFF)
    }

    @Test func roundTripsPanTilt() {
        let bytes = UVCControl.encodeInt32(-131072)
        #expect(bytes == [0x00, 0x00, 0xFE, 0xFF])
        #expect(UVCControl.decodeInt32(bytes[...]) == -131072)
    }
}

@Suite struct DellXUTests {
    /// Values from DDPM_Camera_Settings.json.
    @Test func matchesDDPMPayloads() {
        #expect(DellXU.fieldOfView(.narrow).value == 0x00410110FF)
        #expect(DellXU.fieldOfView(.medium).value == 0x004E0110FF)
        #expect(DellXU.fieldOfView(.wide).value == 0x005A0110FF)
        #expect(DellXU.hdr(true).value == 0x0111FF)
        #expect(DellXU.hdr(false).value == 0x0011FF)
        #expect(DellXU.autoFraming(true).value == 0x010114FF)
        #expect(DellXU.autoFraming(false).value == 0x000114FF)
        #expect(DellXU.cameraTransition(true).value == 0x011014FF)
        #expect(DellXU.cameraTransition(false).value == 0x001014FF)
        #expect(DellXU.trackingSensitivity(.normal).value == 0x011114FF)
        #expect(DellXU.trackingSensitivity(.fast).value == 0x021114FF)
        #expect(DellXU.frameSize(.narrow).value == 0x021214FF)
        #expect(DellXU.frameSize(.standard).value == 0x011214FF)
    }

    @Test func sendsLittleEndianEightBytes() {
        #expect(DellXU.fieldOfView(.wide).payload == [0xFF, 0x10, 0x01, 0x5A, 0x00, 0x00, 0x00, 0x00])
        #expect(DellXU.hdr(true).payload.count == DellXU.commandLength)
    }
}

@Suite struct SettingsTests {
    @Test func decodesPartialJSON() throws {
        let json = Data(#"{"settings":{"brightness":200}}"#.utf8)
        let state = try JSONDecoder().decode(StoredState.self, from: json)
        #expect(state.settings.brightness == 200)
        #expect(state.settings.fieldOfView == .wide)
        #expect(state.customPresets.isEmpty)
    }

    @Test func presetAppliesOnlyImageFields() {
        var settings = CameraSettings()
        settings.fieldOfView = .narrow
        settings.zoom = 250
        let warm = ImagePreset.builtIns.first { $0.id == "warm" }!
        warm.apply(to: &settings)
        #expect(settings.brightness == 169)
        #expect(settings.hdr)
        #expect(settings.fieldOfView == .narrow)
        #expect(settings.zoom == 250)
        #expect(warm.matches(settings))
        #expect(!ImagePreset.builtIns[0].matches(settings))
    }

    @Test func defaultPresetMatchesDefaultSettings() {
        #expect(ImagePreset.builtIns[0].matches(CameraSettings()))
    }
}
