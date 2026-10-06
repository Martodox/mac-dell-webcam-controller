import AppKit
import PreferencePanes
import SwiftUI

/// Principal class of the preference pane (NSPrincipalClass = Dell_Camera_Configurator).
/// System Settings calls every NSPreferencePane method on the main thread.
@objc(Dell_Camera_Configurator)
final class DellCameraPane: NSPreferencePane {
    private var model: CameraViewModel?

    override func loadMainView() -> NSView {
        let host = MainActor.assumeIsolated {
            let model = CameraViewModel()
            self.model = model
            let host = NSHostingView(rootView: PaneRootView(model: model))
            host.frame = NSRect(origin: .zero, size: PaneRootView.size)
            host.autoresizingMask = [.width, .height]
            return host
        }
        mainView = host
        mainViewDidLoad()
        return host
    }

    override func didSelect() {
        MainActor.assumeIsolated { model?.start() }
    }

    override func didUnselect() {
        MainActor.assumeIsolated { model?.stop() }
    }
}
