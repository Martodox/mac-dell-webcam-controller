@preconcurrency import AVFoundation
import AppKit
import SwiftUI

/// Floating window with a live, mirrored preview of the WB7022.
final class PreviewWindowController: NSWindowController, NSWindowDelegate {
    private let model = PreviewModel()
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .utilityWindow],
            backing: .buffered, defer: false)
        window.title = "Dell Webcam WB7022"
        window.titlebarAppearsTransparent = true
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = true
        window.contentAspectRatio = NSSize(width: 16, height: 9)
        window.minSize = NSSize(width: 320, height: 180)
        window.setFrameAutosaveName("DellCameraPreview")
        window.contentView = NSHostingView(rootView: PreviewContent(model: model))
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() {
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        NSApp.activate()
        model.start()
    }

    func windowWillClose(_ notification: Notification) {
        model.stop()
        onClose()
    }
}

@MainActor
final class PreviewModel: ObservableObject {
    enum Status { case starting, running, denied, notFound }

    @Published private(set) var status = Status.starting
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "club.freediver.dell-camera.preview")

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { granted ? self.run() : (self.status = .denied) }
            }
        default:
            status = .denied
        }
    }

    func stop() {
        let session = session
        queue.async { session.stopRunning() }
    }

    func retry() {
        status = .starting
        start()
    }

    private func run() {
        guard let camera = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external], mediaType: .video, position: .unspecified
        ).devices.first(where: {
            $0.modelID.contains("VendorID_16700 ProductID_49173") || $0.localizedName.contains("WB7022")
        }), let input = try? AVCaptureDeviceInput(device: camera) else {
            status = .notFound
            return
        }
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        if session.canAddInput(input) { session.addInput(input) }
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        session.commitConfiguration()
        let session = session
        queue.async { session.startRunning() }
        status = .running
    }
}

private struct PreviewContent: View {
    @ObservedObject var model: PreviewModel

    var body: some View {
        ZStack {
            Color.black
            switch model.status {
            case .starting:
                ProgressView().controlSize(.small)
            case .running:
                PreviewLayer(session: model.session)
            case .denied:
                message("Camera access is turned off for Dell Camera Agent.",
                        button: "Open Privacy & Security…") {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                }
            case .notFound:
                message("Dell Webcam WB7022 is not connected.", button: "Try Again") { model.retry() }
            }
        }
        .ignoresSafeArea()
    }

    private func message(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash").font(.largeTitle)
            Text(text)
            Button(button, action: action)
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding()
    }
}

private struct PreviewLayer: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        // Mirrored like a self-view; what other apps receive is unaffected.
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        let view = NSView()
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
