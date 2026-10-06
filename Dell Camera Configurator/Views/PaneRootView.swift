import CameraKit
import SwiftUI

/// Single-column grouped form modelled on System Settings › Displays.
struct PaneRootView: View {
    /// Fits the detail area of the System Settings window; the form scrolls vertically.
    static let size = CGSize(width: 500, height: 560)

    @ObservedObject var model: CameraViewModel
    @State private var isSavingPreset = false
    @State private var newPresetName = ""
    @State private var isConfirmingReset = false

    var body: some View {
        Form {
            Section { header }
            framing.disabled(!model.isConnected)
            focusAndExposure.disabled(!model.isConnected)
            image.disabled(!model.isConnected)
            background
        }
        .formStyle(.grouped)
        .frame(minWidth: 440, idealWidth: Self.size.width, minHeight: 360, idealHeight: Self.size.height)
        .alert("Save Preset", isPresented: $isSavingPreset) {
            TextField("Preset Name", text: $newPresetName)
            Button("Save") {
                model.saveCurrentAsPreset(named: newPresetName)
                newPresetName = ""
            }
            Button("Cancel", role: .cancel) { newPresetName = "" }
        } message: {
            Text("Saves the current HDR, white balance, brightness, contrast, saturation and sharpness.")
        }
        .confirmationDialog("Restore the default camera settings?", isPresented: $isConfirmingReset) {
            Button("Restore Defaults", role: .destructive) { model.resetToDefaults() }
        } message: {
            Text("Field of view, framing, focus and image settings return to their defaults. Saved presets are kept.")
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "web.camera")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 60, height: 44)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text("Dell Webcam WB7022").font(.headline)
                Text(model.isConnected ? "Connected" : "Not connected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Preview…") { model.openPreview() }
                .disabled(!model.isConnected)
                .help("Opens a live preview window.")
        }
        .padding(.vertical, 2)
    }

    private var framing: some View {
        Section("Framing") {
            Picker("Field of view", selection: model.binding(\.fieldOfView, .fieldOfView)) {
                Text("Narrow (65°)").tag(FieldOfView.narrow)
                Text("Medium (78°)").tag(FieldOfView.medium)
                Text("Wide (90°)").tag(FieldOfView.wide)
            }
            Toggle(isOn: model.binding(\.autoFraming, .autoFraming)) {
                Text("Auto framing")
                Text("Keeps you in frame by zooming and panning automatically.")
            }
            if model.settings.autoFraming {
                Picker("Frame size", selection: model.binding(\.frameSize, .frameSize)) {
                    Text("Standard").tag(FrameSize.standard)
                    Text("Narrow").tag(FrameSize.narrow)
                }
                Picker("Tracking speed", selection: model.binding(\.trackingSensitivity, .trackingSensitivity)) {
                    Text("Normal").tag(TrackingSensitivity.normal)
                    Text("Fast").tag(TrackingSensitivity.fast)
                }
                Toggle("Smooth transitions", isOn: model.binding(\.cameraTransition, .cameraTransition))
            } else {
                ControlSlider("Zoom", value: model.binding(\.zoom, .zoom), range: range(.zoom),
                              minimumSymbol: "minus.magnifyingglass", maximumSymbol: "plus.magnifyingglass")
                Group {
                    ControlSlider("Horizontal", value: model.binding(\.pan, .panTilt), range: model.panRange,
                                  minimumSymbol: "arrow.left", maximumSymbol: "arrow.right")
                    ControlSlider("Vertical", value: model.binding(\.tilt, .panTilt), range: model.tiltRange,
                                  minimumSymbol: "arrow.down", maximumSymbol: "arrow.up")
                }
                .disabled(!isZoomedIn)
                .help(isZoomedIn ? "" : "Zoom in to move the image.")
            }
        }
    }

    private var focusAndExposure: some View {
        Section("Focus and Exposure") {
            Toggle("Autofocus", isOn: model.binding(\.autoFocus, .autoFocus))
            if !model.settings.autoFocus {
                ControlSlider("Focus", value: model.binding(\.focus, .focus), range: range(.focus),
                              minimumSymbol: "camera.macro", maximumSymbol: "mountain.2")
            }
            Picker(selection: model.binding(\.exposurePriority, .exposurePriority)) {
                Text("Exposure").tag(true)
                Text("Frame rate").tag(false)
            } label: {
                Text("Low-light priority")
                Text("Exposure brightens dim scenes by lowering the frame rate.")
            }
            Picker(selection: model.binding(\.antiFlicker, .antiFlicker)) {
                Text("50 Hz").tag(AntiFlicker.hz50)
                Text("60 Hz").tag(AntiFlicker.hz60)
            } label: {
                Text("Anti-flicker")
                Text("Match your mains frequency: 50 Hz in Europe, 60 Hz in North America.")
            }
        }
    }

    private var image: some View {
        Section("Image") {
            LabeledContent("Preset") {
                HStack(spacing: 4) {
                    Picker("Preset", selection: presetSelection) {
                        ForEach(ImagePreset.builtIns) { Text($0.name).tag(Optional($0.id)) }
                        if !model.customPresets.isEmpty {
                            Divider()
                            ForEach(model.customPresets) { Text($0.name).tag(Optional($0.id)) }
                        }
                        if model.activePresetID == nil {
                            Divider()
                            Text("Custom").tag(String?.none)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Menu {
                        Button("Save as New Preset…") { isSavingPreset = true }
                        if let preset = activeCustomPreset {
                            Button("Delete “\(preset.name)”", role: .destructive) { model.deletePreset(preset) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Manage presets")
                }
            }
            Toggle(isOn: model.binding(\.hdr, .hdr)) {
                Text("HDR")
                Text("Balances bright and dark areas. Needs a USB 3 connection.")
            }
            Toggle("Automatic white balance", isOn: model.binding(\.autoWhiteBalance, .autoWhiteBalance))
            if !model.settings.autoWhiteBalance {
                ControlSlider(title: "Temperature", value: model.binding(\.whiteBalance, .whiteBalance),
                              range: range(.whiteBalance),
                              minimumLabel: { Text(kelvin(range(.whiteBalance).min)).font(.caption) },
                              maximumLabel: { Text(kelvin(range(.whiteBalance).max)).font(.caption) })
            }
            ControlSlider("Brightness", value: model.binding(\.brightness, .brightness), range: range(.brightness),
                          minimumSymbol: "sun.min", maximumSymbol: "sun.max")
            ControlSlider("Contrast", value: model.binding(\.contrast, .contrast), range: range(.contrast),
                          minimumSymbol: "circle.lefthalf.filled", maximumSymbol: "circle.lefthalf.filled")
            ControlSlider("Saturation", value: model.binding(\.saturation, .saturation), range: range(.saturation),
                          minimumSymbol: "drop", maximumSymbol: "drop.fill")
            ControlSlider("Sharpness", value: model.binding(\.sharpness, .sharpness), range: range(.sharpness),
                          minimumSymbol: "circle.dotted", maximumSymbol: "smallcircle.filled.circle")
        }
    }

    private var background: some View {
        Section {
            Toggle(isOn: Binding(get: { model.autoApplyEnabled }, set: { model.setAutoApply($0) })) {
                Text("Keep settings applied")
                Text("The camera forgets its settings when it reconnects. A small background agent re-applies them at login, on reconnect and after sleep.")
            }
        } footer: {
            HStack {
                if let error = model.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                Spacer()
                Button("Restore Defaults…") { isConfirmingReset = true }
                    .disabled(!model.isConnected)
            }
        }
    }

    // MARK: Helpers

    private var isZoomedIn: Bool { model.settings.zoom > range(.zoom).min }

    private var activeCustomPreset: ImagePreset? {
        model.customPresets.first { $0.id == model.activePresetID }
    }

    private var presetSelection: Binding<String?> {
        Binding(get: { model.activePresetID },
                set: { id in
                    if let preset = model.allPresets.first(where: { $0.id == id }) { model.apply(preset) }
                })
    }

    private func range(_ control: UVCControl) -> ControlRange {
        model.ranges[control] ?? ControlRange.fallback[control] ?? ControlRange(min: 0, max: 255, defaultValue: 128)
    }

    private func kelvin(_ value: Int) -> String {
        "\(value)K"
    }
}
