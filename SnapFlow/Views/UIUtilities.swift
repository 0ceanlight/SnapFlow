import SwiftUI
import AppKit

// MARK: - Blur background

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material; v.blendingMode = blendingMode; v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material; v.blendingMode = blendingMode
    }
}

// MARK: - Corner radius helpers

extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeft     = RectCorner(rawValue: 1 << 0)
    static let topRight    = RectCorner(rawValue: 1 << 1)
    static let bottomLeft  = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
    static let allCorners: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: RectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        Path(NSBezierPath(roundedRect: NSRect(origin: rect.origin, size: rect.size),
                          xRadius: radius, yRadius: radius).cgPath)
    }
}

// MARK: - Seeded RNG (linear congruential generator)
// Deterministic per event: same seed → same shuffle → same color every render.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: Int) {
        // Mix the seed to avoid poor low-bit distributions
        state = UInt64(bitPattern: Int64(seed)) ^ 6364136223846793005
    }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

// MARK: - MousePositionProxy
// Transparent NSView that tracks the mouse Y position normalised to [0, 1]
// (0 = top, 1 = bottom). Used to decide whether to show the TODO panel.

struct MousePositionProxy: NSViewRepresentable {
    var onNormalizedY: (CGFloat) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let v = TrackingView()
        v.onNormalizedY = onNormalizedY
        return v
    }

    func updateNSView(_ v: TrackingView, context: Context) {
        v.onNormalizedY = onNormalizedY
    }

    class TrackingView: NSView {
        var onNormalizedY: ((CGFloat) -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let old = trackingArea { removeTrackingArea(old) }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .activeAlways, .inVisibleRect],
                owner: self, userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseMoved(with event: NSEvent) {
            guard bounds.height > 0 else { return }
            // Convert from window coords to view coords, then normalise
            let pt = convert(event.locationInWindow, from: nil)
            // NSView: y = 0 at bottom, flip to 0 at top
            let fromTop = 1.0 - (pt.y / bounds.height)
            let clamped  = max(0, min(1, fromTop))
            onNormalizedY?(clamped)
        }
    }
}

// MARK: - Color Adjustment

extension Color {
    func adjusted(saturationDelta: Double = 0, brightnessDelta: Double = 0) -> Color {
        let nsColor = NSColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        
        return Color(
            hue: Double(h),
            saturation: max(0, min(1, Double(s) + saturationDelta)),
            brightness: max(0, min(1, Double(b) + brightnessDelta)),
            opacity: Double(a)
        )
    }
}
