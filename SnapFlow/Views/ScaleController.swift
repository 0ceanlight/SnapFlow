import SwiftUI
import AppKit
import Combine

// MARK: - ScaleController

/// Holds the vertical zoom level and owns the NSEvent key monitor.
/// Before each animated scale change, captures the scroll anchor state
/// so the ZoomScrollSyncer modifier can keep the "Now" line stable.
final class ScaleController: ObservableObject {
    static let defaultScale: CGFloat = 1.5

    @Published var scale: CGFloat = ScaleController.defaultScale

    let minScale: CGFloat = 1.0
    let maxScale: CGFloat = 10.0
    let step: CGFloat = 0.5

    /// Scroll state captured just before each zoom for animation sync.
    var anchorScrollOffset: CGFloat = 0
    var anchorScale: CGFloat = ScaleController.defaultScale

    /// Set by the view once the underlying NSScrollView is discovered.
    weak var scrollView: NSScrollView?

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
                DispatchQueue.main.async { self.zoom(to: min(self.maxScale, self.scale + self.step)) }
                return nil
            } else if ch == "-" || key == 27 {
                DispatchQueue.main.async { self.zoom(to: max(self.minScale, self.scale - self.step)) }
                return nil
            }
            return event
        }
    }

    func remove() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private func zoom(to newScale: CGFloat) {
        guard newScale != scale else { return }
        // Snapshot scroll state BEFORE the animated scale change.
        anchorScale = scale
        anchorScrollOffset = scrollView?.contentView.bounds.origin.y ?? 0
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            scale = newScale
        }
    }
}
