import CameraKit
import Foundation
import SwiftUI
import os

private let log = Logger(subsystem: "club.freediver.dell-camera", category: "pane")

/// Owns the camera connection and the saved state; every edit is persisted and written to the camera.
@MainActor
final class CameraViewModel: ObservableObject {
    @Published private(set) var settings: CameraSettings
    @Published private(set) var customPresets: [ImagePreset]
    @Published private(set) var isConnected = false
    @Published private(set) var ranges = ControlRange.fallback
    @Published private(set) var panRange = ControlRange.panTiltFallback
    @Published private(set) var tiltRange = ControlRange.panTiltFallback
    @Published private(set) var autoApplyEnabled = AgentInstaller.isLoginAgentEnabled
    @Published var lastError: String?

    private var device: UVCDevice?
    private var monitor: UVCDeviceMonitor?
    private var hasStoredState: Bool
    /// USB control requests block, so they run off the main thread, one at a time.
    private let queue = DispatchQueue(label: "club.freediver.dell-camera.pane-uvc")
    private var pendingWrites: [CameraSettings.Field: DispatchWorkItem] = [:]

    init() {
        let stored = SettingsStore.load()
        settings = stored?.settings ?? CameraSettings()
        customPresets = stored?.customPresets ?? []
        hasStoredState = stored != nil
    }

    // MARK: Lifecycle

    func start() {
        guard monitor == nil else { return }
        let monitor = UVCDeviceMonitor { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        self.monitor = monitor
        monitor.start()
        AgentInstaller.refresh()
        autoApplyEnabled = AgentInstaller.isLoginAgentEnabled
    }

    func stop() {
        monitor?.stop()
        monitor = nil
        device = nil
        isConnected = false
    }

    private func handle(_ event: UVCDeviceMonitor.Event) {
        switch event {
        case .attached(let device):
            self.device = device
            isConnected = true
            lastError = nil
            connect(device)
        case .detached:
            device = nil
            isConnected = false
            pendingWrites.values.forEach { $0.cancel() }
            pendingWrites.removeAll()
        }
    }

    /// Reads ranges, then either pushes the saved settings or, on first run, adopts the camera's.
    private func connect(_ device: UVCDevice) {
        let seedFromCamera = !hasStoredState
        let current = settings
        queue.async {
            var ranges = ControlRange.fallback
            for control in [UVCControl.zoom, .focus, .whiteBalance, .brightness, .contrast, .saturation, .sharpness] {
                if let range = try? device.range(control) { ranges[control] = range }
            }
            let panTilt = try? device.panTiltRange()
            var settings = current
            var failures: [String] = []
            if seedFromCamera {
                SettingsApplier.readBack(into: &settings, from: device)
            } else {
                failures = SettingsApplier.applyAll(settings, to: device)
            }
            DispatchQueue.main.async {
                self.ranges = ranges
                if let panTilt {
                    self.panRange = panTilt.pan
                    self.tiltRange = panTilt.tilt
                }
                if seedFromCamera {
                    self.settings = settings
                    self.hasStoredState = true
                    self.save()
                }
                if !failures.isEmpty { self.lastError = "Some settings could not be applied." }
            }
        }
    }

    // MARK: Editing

    func binding<Value>(_ keyPath: WritableKeyPath<CameraSettings, Value>,
                        _ field: CameraSettings.Field) -> Binding<Value> {
        Binding(get: { self.settings[keyPath: keyPath] },
                set: { self.update(keyPath, to: $0, field: field) })
    }

    func update<Value>(_ keyPath: WritableKeyPath<CameraSettings, Value>, to value: Value,
                       field: CameraSettings.Field) {
        settings[keyPath: keyPath] = value
        save()
        write(field)
    }

    /// Moves the digital pan/tilt by `steps` tenths of the available range.
    func nudge(pan: Int = 0, tilt: Int = 0) {
        settings.pan = panRange.clamp(settings.pan + pan * panRange.span / 10)
        settings.tilt = tiltRange.clamp(settings.tilt + tilt * tiltRange.span / 10)
        save()
        write(.panTilt)
    }

    func centerPanTilt() {
        settings.pan = 0
        settings.tilt = 0
        save()
        write(.panTilt)
    }

    func resetToDefaults() {
        settings = CameraSettings()
        save()
        CameraSettings.Field.allCases.forEach(write)
    }

    // MARK: Presets

    var allPresets: [ImagePreset] { ImagePreset.builtIns + customPresets }

    var activePresetID: String? {
        allPresets.first { $0.matches(settings) }?.id
    }

    func apply(_ preset: ImagePreset) {
        preset.apply(to: &settings)
        save()
        ImagePreset.fields.forEach(write)
    }

    func saveCurrentAsPreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        customPresets.append(ImagePreset(name: trimmed, from: settings))
        save()
    }

    func deletePreset(_ preset: ImagePreset) {
        customPresets.removeAll { $0.id == preset.id }
        save()
    }

    // MARK: Agent

    func openPreview() {
        do {
            try AgentInstaller.openPreview()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setAutoApply(_ enabled: Bool) {
        do {
            if enabled { try AgentInstaller.enableLoginAgent() } else { try AgentInstaller.disableLoginAgent() }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            log.error("Login agent \(enabled ? "enable" : "disable") failed: \(error.localizedDescription, privacy: .public)")
        }
        autoApplyEnabled = AgentInstaller.isLoginAgentEnabled
    }

    // MARK: Private

    private func save() {
        var state = StoredState()
        state.settings = settings
        state.customPresets = customPresets
        do {
            try SettingsStore.save(state)
        } catch {
            lastError = "Could not save settings: \(error.localizedDescription)"
        }
    }

    /// Coalesces rapid changes (slider drags) into one USB write per field.
    private func write(_ field: CameraSettings.Field) {
        guard let device else { return }
        pendingWrites[field]?.cancel()
        let snapshot = settings
        let work = DispatchWorkItem { [weak self] in
            do {
                try SettingsApplier.apply(field, of: snapshot, to: device)
            } catch {
                log.error("Writing \(String(describing: field), privacy: .public) failed: \(String(describing: error), privacy: .public)")
                DispatchQueue.main.async { self?.lastError = "Could not set \(field)." }
            }
        }
        pendingWrites[field] = work
        queue.asyncAfter(deadline: .now() + .milliseconds(30), execute: work)
    }
}

extension ControlRange {
    var span: Int { max - min }
}
