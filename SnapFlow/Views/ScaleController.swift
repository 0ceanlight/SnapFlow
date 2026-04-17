import SwiftUI
import AppKit
import Combine

// MARK: - ScaleController

/// Holds the vertical zoom level and owns the NSEvent key monitor.
/// A class (ObservableObject) is used so the monitor closure can safely
/// capture `self` by reference and mutate state without SwiftUI struct-copy issues.
final class ScaleController: ObservableObject {
    /// The default vertical scale (zoom level) on launch.
    /// 1.0 = entire 24h day fits in view. Larger values = more zoomed in.
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
            if ch == "+" || ch == "=" || key == 24 {   // Cmd+
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        self.scale = min(self.maxScale, self.scale + self.step)
                    }
                }
                return nil
            } else if ch == "-" || key == 27 {          // Cmd-
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        self.scale = max(self.minScale, self.scale - self.step)
                    }
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
