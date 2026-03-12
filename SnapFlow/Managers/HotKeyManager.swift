import Cocoa
import Combine

class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()
    
    @Published var isVoiceOrbVisible: Bool = false
    
    var onToggleRuler: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    @Published var settingsTriggerPulse: Bool = false
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    
    private init() {}
    
    func setupHotkey() {
        // Cmd + Shift + S
        let schedulerMask: NSEvent.ModifierFlags = [.command, .shift]
        let schedulerCode: UInt16 = 1 // S
        
        // Cmd + Shift + H
        let rulerMask: NSEvent.ModifierFlags = [.command, .shift]
        let rulerCode: UInt16 = 4 // H
        
        // Cmd + ,
        let settingsMask: NSEvent.ModifierFlags = [.command]
        let settingsCode: UInt16 = 43 // ,
        
        // Global monitor (when app is not active)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == schedulerMask && event.keyCode == schedulerCode {
                self?.toggleVoiceOrb()
            } else if flags == rulerMask && event.keyCode == rulerCode {
                self?.onToggleRuler?()
            } else if flags == settingsMask && event.keyCode == settingsCode {
                self?.pulseSettings()
                self?.onOpenSettings?()
            }
        }
        
        // Local monitor (when app is active)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == schedulerMask && event.keyCode == schedulerCode {
                self?.toggleVoiceOrb()
                return nil // consume event
            } else if flags == rulerMask && event.keyCode == rulerCode {
                self?.onToggleRuler?()
                return nil
            } else if flags == settingsMask && event.keyCode == settingsCode {
                self?.pulseSettings()
                self?.onOpenSettings?()
                return nil
            }
            return event
        }
    }
    
    private func pulseSettings() {
        DispatchQueue.main.async {
            self.settingsTriggerPulse.toggle()
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
