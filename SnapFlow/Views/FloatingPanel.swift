import Cocoa
import SwiftUI

class FloatingPanel<Content: View>: NSPanel {
    init(contentRect: NSRect, content: Content) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.hasShadow = false
        self.isMovableByWindowBackground = false
        self.ignoresMouseEvents = false
        
        // Create hosting view with clear background
        let hostingView = NSHostingView(rootView: content)
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        self.contentView = hostingView
    }
    
    override var canBecomeKey: Bool {
        return true
    }
}
