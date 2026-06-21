import AppKit
import SwiftUI

struct FloatingWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindowIfNeeded(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindowIfNeeded(for: nsView)
        }
    }

    private func configureWindowIfNeeded(for view: NSView) {
        guard let window = view.window else {
            return
        }

        window.level = .floating
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior.insert(.canJoinAllSpaces)
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }
}
