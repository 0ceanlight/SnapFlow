import Cocoa
import Combine

class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()
    
    @Published var isVoiceOrbVisible: Bool = false
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    
    private init() {}
    
    func setupHotkey() {
        // Cmd + Shift + S
        let mask: NSEvent.ModifierFlags = [.command, .shift]
        let keyCode: UInt16 = 1 // S
        
        // Global monitor (when app is not active)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == mask && event.keyCode == keyCode {
                self?.toggleVoiceOrb()
            }
        }
        
        // Local monitor (when app is active)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == mask && event.keyCode == keyCode {
                self?.toggleVoiceOrb()
                return nil // consume event
            }
            return event
        }
    }
    
    func toggleVoiceOrb() {
        DispatchQueue.main.async {
            self.isVoiceOrbVisible.toggle()
        }
    }
    
    deinit {
        if let globalMonitor = globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor = localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }
}
