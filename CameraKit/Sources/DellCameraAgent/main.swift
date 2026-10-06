// Dell Camera Agent: a background app (no Dock icon) with two jobs.
//  • As the login agent, re-apply the saved WB7022 settings whenever the camera appears
//    (login, plug-in, re-enumeration after sleep) and after the Mac wakes.
//  • Show a live preview window when the preference pane asks for one. The pane runs inside
//    System Settings, which macOS never lets use the camera, so the preview lives here.

import AppKit
import CameraKit
import os

let logger = Logger(subsystem: "club.freediver.dell-camera", category: "agent")

final class AgentDelegate: NSObject, NSApplicationDelegate {
    /// True when launchd started us as the login agent, false when opened just for a preview.
    private let isLoginAgent = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == Agent.launchdLabel
    private let queue = DispatchQueue(label: "club.freediver.dell-camera.apply")
    private var pendingApply: DispatchWorkItem?
    private var device: UVCDevice?
    private var monitor: UVCDeviceMonitor?
    private var preview: PreviewWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard isLoginAgent else { return }
        let monitor = UVCDeviceMonitor { [weak self] event in
            switch event {
            case .attached(let device):
                self?.device = device
                self?.scheduleApply(reason: "camera attached")
            case .detached:
                self?.device = nil
                self?.pendingApply?.cancel()
            }
        }
        self.monitor = monitor
        monitor.start()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.scheduleApply(reason: "wake")
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(where: { $0.host == Agent.previewURL.host }) {
            showPreview()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func showPreview() {
        if preview == nil {
            preview = PreviewWindowController { [weak self] in
                guard let self else { return }
                self.preview = nil
                if !self.isLoginAgent { NSApp.terminate(nil) }
            }
        }
        preview?.show()
    }

    /// Waits for the camera firmware to settle, then pushes the saved settings.
    private func scheduleApply(reason: String) {
        pendingApply?.cancel()
        let device = self.device
        let work = DispatchWorkItem {
            guard let device = device ?? UVCDevice.first() else { return }
            guard let state = SettingsStore.load() else {
                logger.info("No saved settings yet, nothing to apply (\(reason, privacy: .public))")
                return
            }
            logger.info("Applying saved settings (\(reason, privacy: .public))")
            SettingsApplier.applyAll(state.settings, to: device)
        }
        pendingApply = work
        queue.asyncAfter(deadline: .now() + 1.5, execute: work)
    }
}

let app = NSApplication.shared
let delegate = AgentDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
