import Cocoa
import Combine

class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()

    @Published var isVoiceOrbVisible: Bool = false

    var onToggleRuler: (() -> Void)?
    @Published var settingsTriggerPulse: Bool = false

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private init() {}

    // Returns true if the event was handled (consume it from local monitor).
    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == [.command, .shift] && event.keyCode == 1 { // Cmd+Shift+S
            toggleVoiceOrb()
            return true
        } else if flags == [.command, .shift] && event.keyCode == 4 { // Cmd+Shift+H
            onToggleRuler?()
            return true
        } else if flags == .command && event.keyCode == 43 { // Cmd+,
            pulseSettings()
            return true
        }
        return false
    }

    func setupHotkey() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return handleKeyEvent(event) ? nil : event
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
