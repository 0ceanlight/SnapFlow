import SwiftUI
import AppKit
import Combine

// MARK: - ScaleController

/// Holds the vertical zoom level and owns the NSEvent key monitor.
/// Scale changes are instant (no animation) so the caller can adjust
/// the scroll offset atomically, keeping the "Now" line stable on screen.
final class ScaleController: ObservableObject {
    static let defaultScale: CGFloat = 1.5

    @Published var scale: CGFloat = ScaleController.defaultScale

    let minScale: CGFloat = 1.0
    let maxScale: CGFloat = 10.0
    let step: CGFloat = 0.5

    private var monitor: Any?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let cmd = event.modifierFlags.contains(.command)
            guard cmd else { return event }
            let key = event.keyCode
            let ch  = event.charactersIgnoringModifiers ?? ""
            if ch == "+" || ch == "=" || key == 24 {
                DispatchQueue.main.async {
                    self.scale = min(self.maxScale, self.scale + self.step)
                }
                return nil
            } else if ch == "-" || key == 27 {
                DispatchQueue.main.async {
                    self.scale = max(self.minScale, self.scale - self.step)
                }
                return nil
            }
            return event
        }
    }

    func remove() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
